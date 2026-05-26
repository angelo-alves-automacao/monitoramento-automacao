#!/usr/bin/env python3
"""
RPA Oracle → PostgreSQL Sync
Sincroniza tabelas ROBO_RPA do Oracle para schema rpa_sync no PostgreSQL.
Executa a cada SYNC_INTERVAL segundos (padrão: 300s / 5min).
"""

import os
import time
import logging
from datetime import datetime

import oracledb
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

load_dotenv()

_thick_initialized = False

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/app/logs/sync.log"),
    ],
)
log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
ORACLE_CONFIG = {
    "user":         os.environ["ORACLE_USER"],
    "password":     os.environ["ORACLE_PASSWORD"],
    "host":         os.environ["ORACLE_HOST"],
    "port":         int(os.getenv("ORACLE_PORT", "1521")),
    "service_name": os.environ["ORACLE_SERVICE"],
}

PG_DSN = (
    f"host={os.environ['PG_HOST']} "
    f"port={os.getenv('PG_PORT', '5432')} "
    f"dbname={os.environ['PG_DB']} "
    f"user={os.environ['PG_USER']} "
    f"password={os.environ['PG_PASSWORD']}"
)

SYNC_INTERVAL = int(os.getenv("SYNC_INTERVAL", "300"))
BATCH_SIZE    = int(os.getenv("BATCH_SIZE", "500"))
ORA_SCHEMA    = "ROBO_RPA"
PG_SCHEMA     = "rpa_sync"

# ── Tabelas ───────────────────────────────────────────────────────────────────
# strategy:
#   upsert        → INSERT ... ON CONFLICT DO UPDATE  (registros que podem ser atualizados)
#   insert_only   → INSERT ... ON CONFLICT DO NOTHING (append-only)
#   full_refresh  → TRUNCATE + UPSERT                 (referências pequenas)
TABLES = [
    # ── Operacionais (upsert) ─────────────────────────────────────────────────
    dict(
        name="HOS_AUTORIZACOES",
        pk="ID",
        delta_col="DT_EXECUCAO",
        strategy="upsert",
        skip_cols=["ANEXOS"],       # CLOB pesado — desnecessário para dashboard
        update_cols=["STATUS", "STATUS_OPERADORA", "STATUS_TASY",
                     "MENSAGEM", "CD_GUIA", "CD_SENHA"],
    ),
    dict(
        name="RPA_HOS_AUTORIZACOES_PENDENTES",
        pk="ID",
        delta_col="DT_EXECUCAO",
        strategy="upsert",
        skip_cols=[],
        update_cols=["STATUS", "STATUS_OPERADORA", "DS_ESTAGIO",
                     "DS_ESTAGIO_FINAL", "MENSAGEM"],
    ),
    dict(
        name="HOS_CONTROLE_CIRURGIAS",
        pk="ID_CONTROLE_CIRURGIA",
        delta_col="DT_ULTIMA_ATUALIZACAO",
        strategy="upsert",
        skip_cols=[],
        update_cols=["IE_STATUS_CIRURGIA", "DS_ESTAGIO", "DT_ULTIMA_ATUALIZACAO",
                     "QT_GUIA_AUTORIZADO", "QT_GUIA_EM_AUTORIZACAO",
                     "QT_GUIA_CANCEL_NEGADO", "STATUS_GERAL",
                     "STATUS_GUIA_CIRURGIA", "STATUS_GUIA_MATMED"],
    ),
    dict(
        name="RPA_HOS_FECHAMENTO_CONTA",
        pk="ID",
        delta_col="DT_EXECUCAO",
        strategy="upsert",
        skip_cols=[],
        update_cols=["STATUS", "MENSAGEM", "NR_PROTOCOLO", "PROTOCOLO"],
    ),
    dict(
        name="HOS_PROTOCOLO_XML",
        pk="ID_PROTOCOLO",
        delta_col="DT_EXECUCAO",
        strategy="upsert",
        skip_cols=[],
        update_cols=["STATUS", "STATUS_DOWNLOAD", "STATUS_EXECUCAO",
                     "MENSAGEM", "ARQUIVO"],
    ),
    dict(
        name="RPA_CONTROLE_EXECUCAO",
        pk="ID_EXECUCAO",
        delta_col="DATA_HORA_INICIO",
        strategy="upsert",
        lookback_hours=8,
        terminal_status=(3, 4),  # CONCLUIDO=3, ERRO=4 — nunca sobrescrever com CANCELADO/outro
        skip_cols=[],
        update_cols=["DATA_HORA_FIM", "ID_STATUS", "OBSERVACOES"],
    ),
    # ── Append-only (insert_only) ─────────────────────────────────────────────
    dict(
        name="RPA_LOGS",
        pk="ID_LOG",
        delta_col="DATA_HORA_LOG",
        strategy="insert_only",
        skip_cols=[],
        update_cols=[],
    ),
    dict(
        name="RPA_ERROS",
        pk="ID_ERRO",
        delta_col="DATA_CRIACAO",
        strategy="insert_only",
        skip_cols=[],
        update_cols=[],
    ),
    # ── Referências (full_refresh — tabelas pequenas de catálogo) ─────────────
    dict(name="RPA_STATUS_EXECUCAO", pk="ID_STATUS",     delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
    dict(name="RPA_UNIDADES",        pk="ID_UNIDADE",    delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
    dict(name="RPA_SCRIPTS",         pk="ID_SCRIPT",     delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
    dict(name="RPA_PROJETOS",        pk="ID_PROJETO",    delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
    dict(name="RPA_COMPUTADORES",    pk="ID_COMPUTADOR", delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
    dict(name="RPA_PROCESSOS",       pk="ID_PROCESSO",   delta_col=None, strategy="full_refresh", skip_cols=[], update_cols=[]),
]


# ── Watermark ─────────────────────────────────────────────────────────────────
def get_watermark(pg_cur, table_name):
    pg_cur.execute(
        "SELECT last_id, last_updated_at "
        "FROM rpa_sync._watermarks WHERE table_name = %s",
        (table_name,),
    )
    row = pg_cur.fetchone()
    if row:
        return row["last_id"] or 0, row["last_updated_at"] or datetime(1970, 1, 1)
    return 0, datetime(1970, 1, 1)


def set_watermark(pg_cur, table_name, last_id, last_updated_at, rows_synced):
    pg_cur.execute(
        """
        INSERT INTO rpa_sync._watermarks
               (table_name, last_id, last_updated_at, rows_last, synced_at)
        VALUES (%s, %s, %s, %s, NOW())
        ON CONFLICT (table_name) DO UPDATE SET
            last_id         = EXCLUDED.last_id,
            last_updated_at = EXCLUDED.last_updated_at,
            rows_last       = EXCLUDED.rows_last,
            synced_at       = NOW()
        """,
        (table_name, last_id, last_updated_at, rows_synced),
    )


# ── Oracle helpers ────────────────────────────────────────────────────────────
def fetch_columns(ora_cur, table_name, skip_cols):
    ora_cur.execute(
        "SELECT COLUMN_NAME FROM ALL_TAB_COLUMNS "
        "WHERE OWNER = :owner AND TABLE_NAME = :tname "
        "ORDER BY COLUMN_ID",
        owner=ORA_SCHEMA,
        tname=table_name,
    )
    return [r[0] for r in ora_cur.fetchall() if r[0] not in skip_cols]


def build_delta_query(table, columns, last_id, last_updated_at):
    col_list = ", ".join(columns)
    pk       = table["pk"]
    delta    = table["delta_col"]
    lookback = table.get("lookback_hours")

    conds = [f"{pk} > {last_id}"]
    if delta:
        ts = last_updated_at.strftime("%Y-%m-%d %H:%M:%S")
        conds.append(f"{delta} > TIMESTAMP '{ts}'")
    if lookback and delta:
        # garante re-sync de registros recentes cujo status pode ter mudado após o watermark
        conds.append(f"{delta} >= SYSDATE - {lookback}/24")

    where = " OR ".join(conds)
    return (
        f"SELECT {col_list} "
        f"FROM {ORA_SCHEMA}.{table['name']} "
        f"WHERE {where} "
        f"ORDER BY {pk}"
    )


def clean_row(row):
    """Converte tipos Oracle não-serializáveis (LOB, etc.) para Python nativo."""
    return [val.read() if hasattr(val, "read") else val for val in row]


def connect_oracle() -> oracledb.Connection:
    """Tenta thin; faz fallback para thick (ORACLE_INSTANT_CLIENT_DIR) se DPY-3015."""
    global _thick_initialized
    try:
        return oracledb.connect(**ORACLE_CONFIG)
    except Exception as e:
        msg = str(e)
        needs_thick = any(code in msg for code in ("DPY-3015", "DPY-2021", "DPY-3001", "password verifier"))
        if needs_thick and not _thick_initialized:
            lib_dir = os.environ.get("ORACLE_INSTANT_CLIENT_DIR")
            if lib_dir:
                oracledb.init_oracle_client(lib_dir=lib_dir)
                _thick_initialized = True
                log.info("Oracle Instant Client (thick mode) inicializado: %s", lib_dir)
                return oracledb.connect(**ORACLE_CONFIG)
        raise


# ── PostgreSQL helpers ────────────────────────────────────────────────────────
def build_upsert_sql(table_name, pk, columns, update_cols, strategy, terminal_status=None):
    pg_table     = f"{PG_SCHEMA}.{table_name.lower()}"
    tbl          = table_name.lower()
    col_names    = ", ".join(c.lower() for c in columns) + ", _synced_at"
    placeholders = ", ".join(["%s"] * len(columns)) + ", NOW()"
    pk_lower     = pk.lower()

    if strategy == "insert_only":
        conflict = f"ON CONFLICT ({pk_lower}) DO NOTHING"
    elif update_cols:
        if terminal_status:
            ids = ", ".join(str(s) for s in terminal_status)
            set_parts = []
            for c in update_cols:
                cl = c.lower()
                if cl in ("id_status", "data_hora_fim"):
                    # não sobrescreve status/fim quando já está num estado terminal
                    set_parts.append(
                        f"{cl} = CASE WHEN {tbl}.id_status IN ({ids}) "
                        f"THEN {tbl}.{cl} ELSE EXCLUDED.{cl} END"
                    )
                else:
                    set_parts.append(f"{cl} = EXCLUDED.{cl}")
            sets = ", ".join(set_parts)
        else:
            sets = ", ".join(f"{c.lower()} = EXCLUDED.{c.lower()}" for c in update_cols)
        conflict = f"ON CONFLICT ({pk_lower}) DO UPDATE SET {sets}, _synced_at = NOW()"
    else:
        conflict = f"ON CONFLICT ({pk_lower}) DO NOTHING"

    return f"INSERT INTO {pg_table} ({col_names}) VALUES ({placeholders}) {conflict}"


# ── Strategies ────────────────────────────────────────────────────────────────
def sync_incremental(ora_cur, pg_cur, table_cfg):
    name     = table_cfg["name"]
    pk       = table_cfg["pk"]
    strategy = table_cfg["strategy"]

    last_id, last_updated_at = get_watermark(pg_cur, name)
    columns  = fetch_columns(ora_cur, name, table_cfg["skip_cols"])
    pk_idx   = columns.index(pk)
    delta    = table_cfg["delta_col"]
    di       = columns.index(delta) if delta and delta in columns else None

    query  = build_delta_query(table_cfg, columns, last_id, last_updated_at)
    upsert = build_upsert_sql(name, pk, columns, table_cfg["update_cols"], strategy, table_cfg.get("terminal_status"))

    ora_cur.execute(query)

    total_rows     = 0
    max_id         = last_id
    max_updated_at = last_updated_at

    while True:
        rows = ora_cur.fetchmany(BATCH_SIZE)
        if not rows:
            break

        batch = [clean_row(r) for r in rows]
        psycopg2.extras.execute_batch(pg_cur, upsert, batch, page_size=BATCH_SIZE)
        pg_cur.connection.commit()

        max_id = max(max_id, max(r[pk_idx] for r in batch))
        if di is not None:
            vals = [r[di] for r in batch if r[di] is not None]
            if vals:
                max_updated_at = max(max_updated_at, max(vals))

        total_rows += len(batch)

    set_watermark(pg_cur, name, max_id, max_updated_at, total_rows)
    pg_cur.connection.commit()
    return total_rows


def sync_full_refresh(ora_cur, pg_cur, table_cfg):
    name    = table_cfg["name"]
    pk      = table_cfg["pk"]
    columns = fetch_columns(ora_cur, name, table_cfg["skip_cols"])

    ora_cur.execute(f"SELECT {', '.join(columns)} FROM {ORA_SCHEMA}.{name}")
    rows = ora_cur.fetchall()
    if not rows:
        return 0

    pg_table     = f"{PG_SCHEMA}.{name.lower()}"
    col_names    = ", ".join(c.lower() for c in columns) + ", _synced_at"
    placeholders = ", ".join(["%s"] * len(columns)) + ", NOW()"
    pk_lower     = pk.lower()
    non_pk       = [c for c in columns if c != pk]
    sets         = ", ".join(f"{c.lower()} = EXCLUDED.{c.lower()}" for c in non_pk)

    sql = (
        f"INSERT INTO {pg_table} ({col_names}) VALUES ({placeholders}) "
        f"ON CONFLICT ({pk_lower}) DO UPDATE SET {sets}, _synced_at = NOW()"
    )
    batch = [clean_row(r) for r in rows]
    psycopg2.extras.execute_batch(pg_cur, sql, batch, page_size=500)
    pg_cur.connection.commit()
    return len(batch)


# ── Main ──────────────────────────────────────────────────────────────────────
def sync_all(ora_conn, pg_conn):
    start = datetime.now()
    log.info("=== Iniciando ciclo de sync ===")
    errors = []

    for table_cfg in TABLES:
        name     = table_cfg["name"]
        strategy = table_cfg["strategy"]
        try:
            with ora_conn.cursor() as ora_cur, \
                 pg_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as pg_cur:

                if strategy == "full_refresh":
                    rows = sync_full_refresh(ora_cur, pg_cur, table_cfg)
                else:
                    rows = sync_incremental(ora_cur, pg_cur, table_cfg)

                log.info(f"  ✓ {name:<40} {rows:>6} linhas  [{strategy}]")

        except Exception as e:
            log.error(f"  ✗ {name}: {e}")
            try:
                pg_conn.rollback()
            except Exception:
                pass
            errors.append(name)

    elapsed = (datetime.now() - start).total_seconds()
    ok  = len(TABLES) - len(errors)
    log.info(f"=== Ciclo em {elapsed:.1f}s — {ok}/{len(TABLES)} tabelas OK"
             + (f" | ERROS: {errors}" if errors else "") + " ===")


def main():
    log.info("RPA Oracle→PG Sync iniciado")
    log.info(f"Oracle: {ORACLE_CONFIG['host']}:{ORACLE_CONFIG['port']}/{ORACLE_CONFIG['service_name']}")
    log.info(f"PG: {os.environ['PG_HOST']}/{os.environ['PG_DB']} schema={PG_SCHEMA}")
    log.info(f"Intervalo: {SYNC_INTERVAL}s | Batch: {BATCH_SIZE}")

    while True:
        ora_conn = None
        pg_conn  = None
        try:
            ora_conn = connect_oracle()
            pg_conn  = psycopg2.connect(PG_DSN)
            sync_all(ora_conn, pg_conn)
        except Exception as e:
            log.error(f"Erro de conexão: {e}")
        finally:
            if ora_conn:
                try: ora_conn.close()
                except Exception: pass
            if pg_conn:
                try: pg_conn.close()
                except Exception: pass

        log.info(f"Próximo sync em {SYNC_INTERVAL}s...")
        time.sleep(SYNC_INTERVAL)


if __name__ == "__main__":
    main()
