-- ============================================================
-- 02_tables.sql
-- Rodar UMA VEZ no PostgreSQL do MAEZO (banco: cibseven)
-- Cria as tabelas no schema rpa_sync espelhando o Oracle
-- Mapeamento: Oracle NUMBER→BIGINT, VARCHAR2→VARCHAR,
--             DATE→TIMESTAMP, CLOB→TEXT, NUMBER(18,2)→NUMERIC(18,2)
-- ============================================================

-- ── Referências ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_status_execucao (
    id_status       INTEGER      PRIMARY KEY,
    nome_status     VARCHAR(20)  NOT NULL,
    descricao       VARCHAR(100),
    ativo           CHAR(1)      DEFAULT 'S',
    data_criacao    TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_unidades (
    id_unidade      INTEGER      PRIMARY KEY,
    nome_unidade    VARCHAR(100) NOT NULL,
    codigo_unidade  VARCHAR(20),
    razao_social    VARCHAR(200),
    cnpj            VARCHAR(18),
    endereco        VARCHAR(200),
    cidade          VARCHAR(50),
    estado          CHAR(2),
    cep             VARCHAR(10),
    telefone        VARCHAR(20),
    email           VARCHAR(100),
    ativo           CHAR(1)      DEFAULT 'S',
    data_criacao    TIMESTAMP,
    data_atualizacao TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_scripts (
    id_script       BIGINT       PRIMARY KEY,
    nome_script     VARCHAR(100) NOT NULL,
    descricao       VARCHAR(500),
    versao          VARCHAR(10)  DEFAULT '1.0',
    ativo           CHAR(1)      DEFAULT 'S',
    data_criacao    TIMESTAMP,
    data_atualizacao TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_computadores (
    id_computador       INTEGER      PRIMARY KEY,
    nome_computador     VARCHAR(30)  NOT NULL,
    endereco_ip         VARCHAR(15),
    notificacao_email   CHAR(1)      DEFAULT 'N',
    ativo               CHAR(1)      DEFAULT 'S',
    data_criacao        TIMESTAMP,
    data_atualizacao    TIMESTAMP,
    _synced_at          TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_projetos (
    id_projeto      BIGINT       PRIMARY KEY,
    id_unidade      INTEGER,
    nome_projeto    VARCHAR(100) NOT NULL,
    descricao       VARCHAR(500),
    responsavel     VARCHAR(100),
    status_projeto  VARCHAR(20)  DEFAULT 'ATIVO',
    data_criacao    TIMESTAMP,
    data_atualizacao TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_processos (
    id_processo     BIGINT   PRIMARY KEY,
    id_projeto      BIGINT,
    id_script       BIGINT,
    ordem_execucao  INTEGER  DEFAULT 1,
    ativo           CHAR(1)  DEFAULT 'S',
    data_criacao    TIMESTAMP,
    data_atualizacao TIMESTAMP,
    _synced_at      TIMESTAMP DEFAULT NOW()
);

-- ── Controle de execução ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_controle_execucao (
    id_execucao     BIGINT       PRIMARY KEY,
    id_processo     BIGINT,
    nome_etapa      VARCHAR(50),
    id_computador   INTEGER,
    usuario_execucao VARCHAR(50),
    data_hora_inicio TIMESTAMP,
    data_hora_fim   TIMESTAMP,
    id_status       INTEGER,
    observacoes     VARCHAR(4000),
    data_criacao    TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exec_inicio
    ON rpa_sync.rpa_controle_execucao (data_hora_inicio);
CREATE INDEX IF NOT EXISTS idx_exec_status
    ON rpa_sync.rpa_controle_execucao (id_status, data_hora_inicio);
CREATE INDEX IF NOT EXISTS idx_exec_processo
    ON rpa_sync.rpa_controle_execucao (id_processo, data_hora_inicio);

-- ── Logs e Erros ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_erros (
    id_erro         BIGINT       PRIMARY KEY,
    nome_rotina     VARCHAR(100) NOT NULL,
    numero_linha    INTEGER,
    codigo_erro     VARCHAR(20),
    mensagem_erro   VARCHAR(2000) NOT NULL,
    caminho_imagem  VARCHAR(500),
    gravidade       VARCHAR(10)  DEFAULT 'MEDIO',
    data_criacao    TIMESTAMP,
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_logs (
    id_log          BIGINT       PRIMARY KEY,
    data_hora_log   TIMESTAMP    NOT NULL,
    tipo_log        VARCHAR(10)  NOT NULL,
    id_execucao     BIGINT,
    id_script       BIGINT,
    tipo_registro   VARCHAR(20),
    mensagem        VARCHAR(4000),
    id_erro         BIGINT,
    cd_registro     VARCHAR(20),
    _synced_at      TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_log_data_tipo
    ON rpa_sync.rpa_logs (data_hora_log, tipo_log);
CREATE INDEX IF NOT EXISTS idx_log_execucao
    ON rpa_sync.rpa_logs (id_execucao, data_hora_log);

-- ── Healthcare — Autorizações ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.hos_autorizacoes (
    id                        BIGINT       PRIMARY KEY,
    controle_execucao         BIGINT,
    nr_atendimento            BIGINT,
    nr_sequencia              BIGINT,
    dt_autorizacao            TIMESTAMP,
    tipo_autorizacao          VARCHAR(100),
    setor_origem              VARCHAR(100),
    cd_convenio               VARCHAR(100),
    cod_carterinha            VARCHAR(50),
    dt_entrada                TIMESTAMP,
    cd_requisicao             VARCHAR(50),
    cd_guia                   VARCHAR(50),
    cd_senha                  VARCHAR(50),
    status                    VARCHAR(50),
    dt_execucao               TIMESTAMP,
    mensagem                  TEXT,
    ds_indicacao              VARCHAR(500),
    cd_procedimento           VARCHAR(500),
    tipo_atendimento          VARCHAR(50),
    ds_convenio               VARCHAR(50),
    ds_tipo_acomodacao        VARCHAR(50),
    cd_procedimento_principal VARCHAR(100),
    cd_prestador              VARCHAR(50),
    nm_paciente               VARCHAR(50),
    dt_nasc_paciente          VARCHAR(50),
    nr_celular_paciente       VARCHAR(50),
    email_paciente            VARCHAR(50),
    medico_solicit            VARCHAR(50),
    crm_medico                VARCHAR(50),
    prontuario                VARCHAR(50),
    status_operadora          VARCHAR(50),
    status_tasy               VARCHAR(50),
    opme                      INTEGER,
    carater_atendimento       INTEGER,
    internacao                INTEGER,
    sequencia_agenda          BIGINT,
    cd_estabelecimento        BIGINT,
    cd_ult_evol_med           VARCHAR(50),
    _synced_at                TIMESTAMP    DEFAULT NOW()
    -- ANEXOS omitido (CLOB não necessário para dashboard)
);

CREATE INDEX IF NOT EXISTS idx_hos_aut_dt_exec
    ON rpa_sync.hos_autorizacoes (dt_execucao);
CREATE INDEX IF NOT EXISTS idx_hos_aut_status
    ON rpa_sync.hos_autorizacoes (status, dt_execucao);
CREATE INDEX IF NOT EXISTS idx_hos_aut_tipo
    ON rpa_sync.hos_autorizacoes (tipo_autorizacao, dt_execucao);
CREATE INDEX IF NOT EXISTS idx_hos_aut_convenio
    ON rpa_sync.hos_autorizacoes (ds_convenio, dt_execucao);

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_hos_autorizacoes_pendentes (
    id                  BIGINT       PRIMARY KEY,
    guia_principal      VARCHAR(100),
    nr_sequencia        BIGINT,
    cd_autorizacao      VARCHAR(50),
    cod_carterinha      VARCHAR(50),
    dt_execucao         TIMESTAMP,
    dt_autorizacao      TIMESTAMP,
    dt_entrada          TIMESTAMP,
    tipo_autorizacao    VARCHAR(100),
    cd_senha            VARCHAR(50),
    ds_estagio          VARCHAR(200),
    status              VARCHAR(50),
    mensagem            VARCHAR(4000),
    cd_convenio         BIGINT,
    nr_atendimento      VARCHAR(20),
    ds_estagio_final    VARCHAR(100),
    status_operadora    VARCHAR(100),
    tipo_atendimento    VARCHAR(50),
    nome_paciente       VARCHAR(500),
    cd_estabelecimento  BIGINT,
    usuario_criacao     VARCHAR(50),
    dt_nasc_paciente    VARCHAR(20),
    _synced_at          TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pend_status
    ON rpa_sync.rpa_hos_autorizacoes_pendentes (status);
CREATE INDEX IF NOT EXISTS idx_pend_tipo
    ON rpa_sync.rpa_hos_autorizacoes_pendentes (tipo_autorizacao, status);

-- ── Healthcare — Cirurgias ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.hos_controle_cirurgias (
    id_controle_cirurgia    BIGINT       PRIMARY KEY,
    nr_atendimento          BIGINT,
    cd_pessoa_fisica        BIGINT,
    nm_paciente             VARCHAR(255),
    dt_criacao              TIMESTAMP,
    cd_procedimento         BIGINT,
    ds_procedimento         VARCHAR(255),
    dt_prevista_cirurgia    TIMESTAMP,
    ie_status_cirurgia      VARCHAR(50),
    dt_ultima_atualizacao   TIMESTAMP,
    cd_convenio             BIGINT,
    ds_convenio             VARCHAR(100),
    dt_autorizacao          TIMESTAMP,
    ds_estagio              VARCHAR(255),
    dt_retorno_autorizacao  TIMESTAMP,
    qt_pedidos_autorizacao  INTEGER,
    cd_medico_solicitante   BIGINT,
    nm_medico_solicitante   VARCHAR(255),
    cd_medico_executante    BIGINT,
    nm_medico_executante    VARCHAR(255),
    dt_inicio_cirurgia      TIMESTAMP,
    dt_termino_cirurgia     TIMESTAMP,
    ds_motivo_cancelamento  VARCHAR(500),
    observacoes             VARCHAR(1000),
    nr_guia_principal       VARCHAR(50),
    ie_tipo_acomodacao      VARCHAR(50),
    dt_alta                 TIMESTAMP,
    qt_guia_necessidade     INTEGER,
    qt_guia_cotacao         INTEGER,
    qt_guia_autorizado      INTEGER,
    status_cirurgia         VARCHAR(1000),
    qt_guia_em_autorizacao  INTEGER,
    qt_guia_cancel_negado   INTEGER,
    qt_guia_auditoria       INTEGER,
    qt_guia_matmed          INTEGER,
    status_guia_matmed      VARCHAR(500),
    status_guia_cirurgia    VARCHAR(500),
    status_geral            VARCHAR(500),
    _synced_at              TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cirug_status
    ON rpa_sync.hos_controle_cirurgias (ie_status_cirurgia);
CREATE INDEX IF NOT EXISTS idx_cirug_atualizacao
    ON rpa_sync.hos_controle_cirurgias (dt_ultima_atualizacao);
CREATE INDEX IF NOT EXISTS idx_cirug_prevista
    ON rpa_sync.hos_controle_cirurgias (dt_prevista_cirurgia);

-- ── Healthcare — Faturamento ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rpa_sync.rpa_hos_fechamento_conta (
    id                      BIGINT          PRIMARY KEY,
    controle_execucao       BIGINT,
    dt_execucao             TIMESTAMP,
    nr_atendimento          BIGINT,
    nr_conta                BIGINT,
    nr_protocolo            BIGINT,
    dt_criacao_atendimento  TIMESTAMP,
    tipo_atendimento        VARCHAR(50),
    dt_desfecho             TIMESTAMP,
    convenio                VARCHAR(100),
    status                  VARCHAR(100),
    mensagem                VARCHAR(4000),
    protocolo               VARCHAR(100),
    total_conta             NUMERIC(18,2),
    ds_setor_atendimento    VARCHAR(200),
    cd_estabelecimento      BIGINT,
    _synced_at              TIMESTAMP       DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fech_dt_exec
    ON rpa_sync.rpa_hos_fechamento_conta (dt_execucao);
CREATE INDEX IF NOT EXISTS idx_fech_status
    ON rpa_sync.rpa_hos_fechamento_conta (status, dt_execucao);
CREATE INDEX IF NOT EXISTS idx_fech_convenio
    ON rpa_sync.rpa_hos_fechamento_conta (convenio, dt_execucao);

CREATE TABLE IF NOT EXISTS rpa_sync.hos_protocolo_xml (
    id_protocolo            BIGINT       PRIMARY KEY,
    nr_seq_protocolo        BIGINT,
    nr_protocolo            VARCHAR(50),
    tipo_protocolo          VARCHAR(50),
    qt_contas               INTEGER,
    status                  VARCHAR(20),
    ds_convenio             VARCHAR(100),
    disponibilidade         VARCHAR(20),
    inconsistencias         VARCHAR(255),
    dt_fech_protocolo       TIMESTAMP,
    dt_mesano_referencia    TIMESTAMP,
    dt_criacao              TIMESTAMP,
    nm_usuario              VARCHAR(20),
    status_download         VARCHAR(50),
    mensagem                VARCHAR(500),
    arquivo                 VARCHAR(200),
    dt_execucao             TIMESTAMP,
    status_execucao         VARCHAR(50),
    _synced_at              TIMESTAMP    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_proto_dt_exec
    ON rpa_sync.hos_protocolo_xml (dt_execucao);
CREATE INDEX IF NOT EXISTS idx_proto_status
    ON rpa_sync.hos_protocolo_xml (status_execucao, dt_execucao);
