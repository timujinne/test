#!/bin/bash
# ============================================
# Скрипт безопасной инициализации PostgreSQL
# для Elixir/Phoenix приложений
# ============================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Безопасная инициализация PostgreSQL${NC}"
echo -e "${CYAN}==========================================${NC}"

# Переменные окружения с проверкой
APP_DB_USER="${APP_DB_USER:-app_user}"
APP_DB_PASSWORD="${APP_DB_PASSWORD}"
APP_DB_NAME="${APP_DB_NAME:-app_production}"

# Проверка обязательных параметров
if [ -z "$APP_DB_PASSWORD" ]; then
    echo -e "${RED}ОШИБКА: Не установлена переменная APP_DB_PASSWORD${NC}"
    exit 1
fi

echo -e "${YELLOW}База данных:${NC} ${APP_DB_NAME}"
echo -e "${YELLOW}Пользователь:${NC} ${APP_DB_USER}"
echo ""

# Подключение к PostgreSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- ========================================
    -- 1. Создание роли приложения
    -- ========================================
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_DB_USER}') THEN
            CREATE ROLE ${APP_DB_USER} WITH LOGIN PASSWORD '${APP_DB_PASSWORD}';
            RAISE NOTICE '✓ Роль ${APP_DB_USER} создана';
        ELSE
            RAISE NOTICE '⚠ Роль ${APP_DB_USER} уже существует';
        END IF;
    END
    \$\$;

    -- ========================================
    -- 2. Создание базы данных
    -- ========================================
    SELECT 'CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${APP_DB_NAME}')\gexec

    -- ========================================
    -- 3. Настройка безопасности
    -- ========================================

    -- Отзыв всех привилегий PUBLIC
    REVOKE ALL ON DATABASE ${APP_DB_NAME} FROM PUBLIC;

    -- Базовые права для приложения
    GRANT CONNECT ON DATABASE ${APP_DB_NAME} TO ${APP_DB_USER};

    -- Ограничения роли
    ALTER ROLE ${APP_DB_USER}
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION
        NOBYPASSRLS
        CONNECTION LIMIT 50;

    -- Настройка таймаутов для безопасности
    ALTER ROLE ${APP_DB_USER} SET statement_timeout = '30s';
    ALTER ROLE ${APP_DB_USER} SET idle_in_transaction_session_timeout = '60s';

    \echo '✓ Базовая конфигурация безопасности применена'

EOSQL

# Подключение к созданной базе для настройки схемы
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$APP_DB_NAME" <<-EOSQL
    -- ========================================
    -- 4. Настройка прав на схему public
    -- ========================================

    -- Владелец схемы
    ALTER SCHEMA public OWNER TO ${APP_DB_USER};

    -- Права на схему
    GRANT USAGE, CREATE ON SCHEMA public TO ${APP_DB_USER};

    -- Права на все существующие таблицы
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${APP_DB_USER};

    -- Права на все будущие таблицы
    ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_DB_USER} IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_DB_USER};

    -- Права на последовательности (для auto-increment)
    GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${APP_DB_USER};
    ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_DB_USER} IN SCHEMA public
        GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${APP_DB_USER};

    -- Права на функции
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ${APP_DB_USER};
    ALTER DEFAULT PRIVILEGES FOR ROLE ${APP_DB_USER} IN SCHEMA public
        GRANT EXECUTE ON FUNCTIONS TO ${APP_DB_USER};

    \echo '✓ Права на схему public настроены'

    -- ========================================
    -- 5. Установка расширений
    -- ========================================

    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    \echo '✓ Расширение uuid-ossp установлено'

    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
    \echo '✓ Расширение pgcrypto установлено'

    CREATE EXTENSION IF NOT EXISTS "citext";
    \echo '✓ Расширение citext установлено'

    -- Опционально: TimescaleDB (для временных рядов)
    -- Раскомментируйте если нужно:
    -- CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
    -- \echo '✓ Расширение timescaledb установлено'

    -- ========================================
    -- 6. Создание служебных функций
    -- ========================================

    -- Функция обновления updated_at
    CREATE OR REPLACE FUNCTION trigger_set_timestamp()
    RETURNS TRIGGER AS \$\$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    \$\$ LANGUAGE plpgsql;

    \echo '✓ Служебные функции созданы'

EOSQL

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  ✓ База данных успешно инициализирована${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${CYAN}Информация:${NC}"
echo -e "  База данных: ${GREEN}${APP_DB_NAME}${NC}"
echo -e "  Пользователь: ${GREEN}${APP_DB_USER}${NC}"
echo -e "  Макс. подключений: ${YELLOW}50${NC}"
echo -e "  Таймаут запроса: ${YELLOW}30s${NC}"
echo ""
echo -e "${CYAN}Установленные расширения:${NC}"
echo -e "  • uuid-ossp (генерация UUID)"
echo -e "  • pgcrypto (криптография)"
echo -e "  • citext (регистронезависимый текст)"
echo ""
echo -e "${YELLOW}⚠ ВАЖНО: Регулярно меняйте пароли!${NC}"
echo -e "${YELLOW}⚠ ВАЖНО: Используйте SSL подключения в production!${NC}"
