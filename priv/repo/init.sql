-- ================================================
-- BINANCE TRADING SYSTEM - DATABASE INITIALIZATION
-- PostgreSQL with TimescaleDB Extension
-- ================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ================================================
-- CREATE SCHEMAS
-- ================================================

-- Trading schema - для торговых данных
CREATE SCHEMA IF NOT EXISTS trading;
COMMENT ON SCHEMA trading IS 'Trading operations, orders, positions, strategies';

-- Analytics schema - для аналитики и метрик
CREATE SCHEMA IF NOT EXISTS analytics;
COMMENT ON SCHEMA analytics IS 'Analytics, metrics, aggregations';

-- Audit schema - для аудита и логирования
CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA audit IS 'Audit logs, security events, compliance';

-- ================================================
-- GRANT PERMISSIONS
-- ================================================

GRANT ALL ON SCHEMA trading TO postgres;
GRANT ALL ON SCHEMA analytics TO postgres;
GRANT ALL ON SCHEMA audit TO postgres;

-- ================================================
-- HELPER FUNCTIONS
-- ================================================

-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION trading.updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trading.updated_at_timestamp() IS 'Automatically update updated_at timestamp';

-- Функция для аудита изменений
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    INSERT INTO audit.change_log (
      table_name,
      operation,
      old_data,
      changed_by,
      changed_at
    ) VALUES (
      TG_TABLE_NAME,
      TG_OP,
      row_to_json(OLD),
      current_user,
      NOW()
    );
    RETURN OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    INSERT INTO audit.change_log (
      table_name,
      operation,
      old_data,
      new_data,
      changed_by,
      changed_at
    ) VALUES (
      TG_TABLE_NAME,
      TG_OP,
      row_to_json(OLD),
      row_to_json(NEW),
      current_user,
      NOW()
    );
    RETURN NEW;
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO audit.change_log (
      table_name,
      operation,
      new_data,
      changed_by,
      changed_at
    ) VALUES (
      TG_TABLE_NAME,
      TG_OP,
      row_to_json(NEW),
      current_user,
      NOW()
    );
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit.log_changes() IS 'Log all DML operations for audit';

-- ================================================
-- AUDIT TABLES
-- ================================================

-- Таблица для логирования изменений
CREATE TABLE IF NOT EXISTS audit.change_log (
  id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL,
  old_data JSONB,
  new_data JSONB,
  changed_by TEXT NOT NULL,
  changed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_change_log_table_name ON audit.change_log(table_name);
CREATE INDEX IF NOT EXISTS idx_change_log_changed_at ON audit.change_log(changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_change_log_operation ON audit.change_log(operation);

COMMENT ON TABLE audit.change_log IS 'Audit log for all database changes';

-- ================================================
-- UTILITY FUNCTIONS
-- ================================================

-- Функция для генерации UUID v7 (timestamp-based)
CREATE OR REPLACE FUNCTION public.uuid_generate_v7()
RETURNS UUID AS $$
DECLARE
  unix_ts_ms BIGINT;
  uuid_bytes BYTEA;
BEGIN
  unix_ts_ms = (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
  uuid_bytes = SET_BYTE(
    SET_BYTE(
      gen_random_bytes(16),
      0,
      (unix_ts_ms >> 40)::BIT(8)::INTEGER
    ),
    1,
    (unix_ts_ms >> 32)::BIT(8)::INTEGER
  );
  uuid_bytes = SET_BYTE(uuid_bytes, 2, (unix_ts_ms >> 24)::BIT(8)::INTEGER);
  uuid_bytes = SET_BYTE(uuid_bytes, 3, (unix_ts_ms >> 16)::BIT(8)::INTEGER);
  uuid_bytes = SET_BYTE(uuid_bytes, 4, (unix_ts_ms >> 8)::BIT(8)::INTEGER);
  uuid_bytes = SET_BYTE(uuid_bytes, 5, (unix_ts_ms)::BIT(8)::INTEGER);
  uuid_bytes = SET_BYTE(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112); -- version 7
  uuid_bytes = SET_BYTE(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128); -- variant
  RETURN encode(uuid_bytes, 'hex')::UUID;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION public.uuid_generate_v7() IS 'Generate UUID v7 (timestamp-based, sortable)';

-- ================================================
-- PERFORMANCE TUNING
-- ================================================

-- Включаем параллельные запросы для больших таблиц
ALTER DATABASE binance_trading_dev SET max_parallel_workers_per_gather = 4;
ALTER DATABASE binance_trading_dev SET effective_cache_size = '1GB';

-- ================================================
-- COMPLETION MESSAGE
-- ================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Database initialization completed successfully!';
  RAISE NOTICE '   - TimescaleDB extension enabled';
  RAISE NOTICE '   - Schemas created: trading, analytics, audit';
  RAISE NOTICE '   - Helper functions installed';
  RAISE NOTICE '   - Audit logging configured';
END $$;
