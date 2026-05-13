-- ============================================================
-- 01_schema.sql
-- Rodar UMA VEZ no PostgreSQL do MAEZO (banco: cibseven)
-- Cria o schema rpa_sync e a tabela de controle de watermark
-- ============================================================

CREATE SCHEMA IF NOT EXISTS rpa_sync;

-- Controle de sincronização incremental
CREATE TABLE IF NOT EXISTS rpa_sync._watermarks (
    table_name      VARCHAR(100) PRIMARY KEY,
    last_id         BIGINT      DEFAULT 0,
    last_updated_at TIMESTAMP   DEFAULT '1970-01-01 00:00:00',
    rows_last       INTEGER     DEFAULT 0,
    synced_at       TIMESTAMP   DEFAULT NOW()
);

-- Inicializar watermarks para todas as tabelas
INSERT INTO rpa_sync._watermarks (table_name) VALUES
    ('HOS_AUTORIZACOES'),
    ('RPA_HOS_AUTORIZACOES_PENDENTES'),
    ('HOS_CONTROLE_CIRURGIAS'),
    ('RPA_HOS_FECHAMENTO_CONTA'),
    ('HOS_PROTOCOLO_XML'),
    ('RPA_CONTROLE_EXECUCAO'),
    ('RPA_LOGS'),
    ('RPA_ERROS'),
    ('RPA_STATUS_EXECUCAO'),
    ('RPA_UNIDADES'),
    ('RPA_SCRIPTS'),
    ('RPA_PROJETOS'),
    ('RPA_COMPUTADORES'),
    ('RPA_PROCESSOS')
ON CONFLICT (table_name) DO NOTHING;
