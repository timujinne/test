# Binance Trading System - Elixir Umbrella Project

Production-ready система для управления криптокошельками Binance на Elixir/Phoenix.

## Структура проекта

```
binance_system/
├── apps/
│   ├── shared_data/       # Общие схемы БД, Ecto Repo, шифрование
│   ├── data_collector/    # Binance API/WebSocket интеграция
│   ├── trading_engine/    # Торговые стратегии и логика
│   └── dashboard_web/     # Phoenix LiveView интерфейс
├── config/                # Конфигурация приложений
└── mix.exs               # Корневой конфиг Umbrella проекта
```

## Технологический стек

- **Elixir** 1.14+
- **Phoenix** 1.7+
- **PostgreSQL** 15 + TimescaleDB
- **Phoenix LiveView** для real-time UI
- **Cloak** для шифрования API ключей
- **Binance API** интеграция

## Быстрый старт

### Требования

- Elixir 1.14+ и Erlang/OTP 25+
- PostgreSQL 15+
- Node.js 18+ (для Phoenix assets)

### Установка зависимостей

```bash
# Установить зависимости всех приложений
mix deps.get

# Настроить базу данных
cd apps/shared_data
mix ecto.create
mix ecto.migrate
cd ../..

# Запустить приложение
mix phx.server
```

### С Docker

```bash
# Запустить PostgreSQL и Redis
make start

# Войти в dev контейнер
docker-compose exec dev bash

# Внутри контейнера
mix deps.get
mix ecto.setup
mix phx.server
```

## Приложения

### SharedData
Общие данные и схемы БД для всех приложений.

- Ecto Repo
- Cloak Vault для шифрования
- Схемы: User, ApiCredential, Account, Trade, Order, Balance, Setting

### DataCollector
Сбор данных с Binance API.

- REST API клиент с rate limiting
- WebSocket streams
- Market data кеширование

### TradingEngine
Торговая логика и стратегии.

- Account-based trader processes
- Торговые стратегии (Naive, Grid, DCA)
- Order management
- Risk management

### DashboardWeb
Phoenix LiveView веб-интерфейс.

- Trading dashboard
- Portfolio overview
- Settings management
- Trade history

## Конфигурация

Скопируйте `.env.example` в `.env` и заполните переменные:

```bash
BINANCE_API_KEY=your_api_key
BINANCE_SECRET_KEY=your_secret_key
CLOAK_KEY=your_encryption_key
SECRET_KEY_BASE=your_phoenix_secret
DATABASE_URL=postgres://postgres:postgres@localhost/binance_trading_dev
```

## Разработка

```bash
# Запустить тесты
mix test

# Форматировать код
mix format

# Проверить качество кода
mix credo

# Запустить статический анализ
mix dialyzer
```

## Deployment

```bash
# Собрать production release
MIX_ENV=prod mix release

# Запустить release
_build/prod/rel/binance_system/bin/binance_system start
```

## Документация

См. полную документацию в корне проекта:

- `IMPLEMENTATION_PLAN.md` - План реализации
- `QUICKSTART.md` - Быстрый старт
- `README.md` - Основная документация
- `SKILLS_GUIDE.md` - Руководство по Skills

## Лицензия

MIT
