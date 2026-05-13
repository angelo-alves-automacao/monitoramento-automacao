# AUSTA — Stack de Monitoramento Independente

Stack de observabilidade separada do MAEZO. Roda Grafana e Prometheus em portas
diferentes para não conflitar com o stack MAEZO, e sobrevive a um `docker compose down`
no MAEZO.

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  AUSTA Monitoring Stack (este compose)                                       │
│                                                                              │
│  grafana:3001      ── dashboards: MAEZO, RPA Healthcare, RPA Operations      │
│  prometheus:9091   ── scrape: workers, cib7, kafka, postgres, node, cadvisor │
│  oracle_sync       ── Oracle ROBO_RPA → PostgreSQL rpa_sync (5min)          │
│                                                                              │
│  Durante a transição: reutiliza os exporters do MAEZO via maestro_local      │
│    kafka_exporter:9308, postgres_exporter:9187, cadvisor:8080                │
│    node_exporter: host.docker.internal:9100                                  │
└─────────────────────────────────────────┬────────────────────────────────────┘
                                          │ rede maestro_local
┌─────────────────────────────────────────▼────────────────────────────────────┐
│  MAEZO Stack (Healthcare-Orchest)                                            │
│  grafana:3000  prometheus:9090  postgres:5432  kafka:9092  cib7:8080         │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Princípio:** se o MAEZO cair, o monitoramento continua rodando.

---

## Portas

| Serviço    | Host  | Container | Observação                  |
|------------|-------|-----------|-----------------------------|
| Grafana    | 3001  | 3000      | MAEZO usa 3000              |
| Prometheus | 9091  | 9090      | MAEZO usa 9090              |

---

## Estrutura de arquivos

```
monitoramento-automacao/
├── compose.monitoring.yml
├── .env.example                    ← copiar para .env e preencher
├── .gitignore
│
├── config/
│   ├── prometheus/
│   │   └── prometheus.yml          ← scrape jobs (workers, cib7, infra)
│   └── grafana/
│       └── provisioning/
│           ├── datasources/
│           │   ├── prometheus.yaml         ← uid: prometheus-austa
│           │   ├── postgres_cibseven.yaml  ← uid: cibseven-pg
│           │   └── rpa_sync.yaml           ← uid: rpa-sync-pg
│           ├── dashboards/
│           │   ├── dashboards.yml
│           │   ├── container-health.json
│           │   ├── maezo-workers.json
│           │   ├── maezo-bpmn.json
│           │   ├── maezo-instance-detail.json
│           │   └── maezo-rc-ops.json
│           └── alerting/
│               ├── contact_points.yaml
│               ├── notification_policies.yaml
│               └── rules_infra.yaml
│
├── sync/
│   ├── Dockerfile                  ← Python 3.12-slim + oracledb thin mode
│   ├── requirements.txt
│   └── sync_oracle_to_pg.py        ← script de sincronização Oracle→PG
│
└── sql/
    ├── 01_schema.sql               ← cria schema rpa_sync + tabela _watermarks
    └── 02_tables.sql               ← cria as 13 tabelas no PostgreSQL
```

---

## Pré-requisitos

- Docker + Docker Compose v2
- Rede `maestro_local` existente (criada pelo MAEZO ao subir)
- PostgreSQL do MAEZO acessível em `postgres:5432` na rede
- Acesso TCP ao Oracle Tasy na porta 1521

---

## Instalação passo a passo

### 1. Preparar o .env

```bash
cp .env.example .env
# Editar .env com as credenciais reais
```

Variáveis obrigatórias:

| Variável          | Descrição                                       |
|-------------------|-------------------------------------------------|
| `GF_ADMIN_PASSWORD` | Senha do admin do Grafana                     |
| `ORACLE_USER`     | Usuário Oracle com SELECT em ROBO_RPA           |
| `ORACLE_PASSWORD` | Senha Oracle                                    |
| `ORACLE_HOST`     | IP ou hostname do Oracle                        |
| `ORACLE_SERVICE`  | Nome do service (ex: TASY)                      |
| `PG_PASSWORD`     | Senha do PostgreSQL do MAEZO                    |

### 2. Criar o schema rpa_sync no PostgreSQL do MAEZO

Rodar os scripts **na ordem** no banco `cibseven`:

```bash
# Via psql direto no container do MAEZO
docker exec -i maezo-infra-postgres-1 psql -U maestro -d cibseven \
  < sql/01_schema.sql

docker exec -i maezo-infra-postgres-1 psql -U maestro -d cibseven \
  < sql/02_tables.sql
```

### 3. Subir o stack

```bash
docker compose -f compose.monitoring.yml up -d --build

# Verificar
docker compose -f compose.monitoring.yml ps
docker logs -f austa-oracle-sync
```

### 4. Acessar o Grafana

- URL: http://localhost:3001
- Usuário: `admin`
- Senha: valor de `GF_ADMIN_PASSWORD` no `.env`

---

## Dashboards provisionados

| Dashboard                  | UID                    | Datasource       |
|----------------------------|------------------------|------------------|
| Container Health           | container-health-austa | prometheus-austa |
| MAEZO — Workers Overview   | maezo-workers-overview | prometheus-austa |
| MAEZO — BPMN Processes     | maezo-bpmn-workers     | prometheus-austa |
| MAEZO — Instâncias BPMN    | maezo-instance-detail  | cibseven-pg      |
| MAEZO — Operações RC       | maezo-rc-ops           | cibseven-pg      |

> **A criar:** RPA Healthcare (`rpa-healthcare`) e RPA Operations (`rpa-operations`)
> com datasource `rpa-sync-pg`. Queries documentadas em
> `C:\BPMN\Healthcare-Orchest\ignorar\Fase2\dashboard_rpa_healthcare.md`.

---

## Oracle → PostgreSQL Sync

O container `oracle_sync` sincroniza as tabelas do schema `ROBO_RPA` do Oracle Tasy
para o schema `rpa_sync` no PostgreSQL do MAEZO a cada 5 minutos (configurável via
`SYNC_INTERVAL`).

### Estratégias por tabela

| Estratégia      | Tabelas                                                                                       |
|-----------------|-----------------------------------------------------------------------------------------------|
| `upsert`        | HOS_AUTORIZACOES, RPA_HOS_AUTORIZACOES_PENDENTES, HOS_CONTROLE_CIRURGIAS, RPA_HOS_FECHAMENTO_CONTA, HOS_PROTOCOLO_XML, RPA_CONTROLE_EXECUCAO |
| `insert_only`   | RPA_LOGS, RPA_ERROS                                                                           |
| `full_refresh`  | RPA_STATUS_EXECUCAO, RPA_UNIDADES, RPA_SCRIPTS, RPA_PROJETOS, RPA_COMPUTADORES, RPA_PROCESSOS |

### Verificar status do sync

```bash
# Logs em tempo real
docker logs -f austa-oracle-sync

# Watermarks no PostgreSQL
docker exec maezo-infra-postgres-1 psql -U maestro -d cibseven -c \
  "SELECT table_name, last_id, last_updated_at, rows_last, NOW() - synced_at AS atraso FROM rpa_sync._watermarks ORDER BY synced_at DESC;"
```

### Forçar re-sync completo de uma tabela

```sql
UPDATE rpa_sync._watermarks
SET last_id = 0, last_updated_at = '1970-01-01'
WHERE table_name = 'HOS_AUTORIZACOES';
```

---

## Alertas

Configurados via provisioning em `config/grafana/provisioning/alerting/`:

- **Disco**: aviso >80%, crítico >90%
- **RAM**: aviso >80%, crítico >90%
- **CPU**: crítico >90% por 5 minutos contínuos
- **Containers**: offline (ausente do cAdvisor por 1m) ou crash loop

Canais de notificação: Zoho Cliq (webhook) + Email. Configurar via `.env`:

```
N8N_GRAFANA_WEBHOOK_URL=https://cliq.zoho.com/api/v2/channelsbyname/.../message?zapikey=...
GRAFANA_ALERT_EMAIL=ti@austa.com.br,oncall@austa.com.br
```

---

## Transição: após remover o observability do MAEZO

Quando remover o `compose.observability.yml` do MAEZO:

1. Descomentar `node_exporter`, `cadvisor`, `kafka_exporter`, `postgres_exporter`
   no `compose.monitoring.yml`
2. Atualizar os targets no `config/prometheus/prometheus.yml`:
   - `cadvisor:8080` → `austa-cadvisor:8080`
   - `kafka_exporter:9308` → `austa-kafka-exporter:9308`
   - `postgres_exporter:9187` → `austa-postgres-exporter:9187`
   - `host.docker.internal:9100` → `localhost:9100` (node_exporter em host mode)

---

## Operação

```bash
# Subir
docker compose -f compose.monitoring.yml up -d --build

# Parar
docker compose -f compose.monitoring.yml down

# Recarregar config do Prometheus sem restart
curl -X POST http://localhost:9091/-/reload

# Status dos containers
docker compose -f compose.monitoring.yml ps
```
