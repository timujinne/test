# Binance Trading System - Development Guide

## Структура реализации

Проект успешно инициализирован со следующей структурой:

### ✅ Фаза 1: Umbrella Project (Completed)
- Создана структура Elixir Umbrella проекта
- Настроены 4 приложения:
  - `shared_data` - База данных, схемы, шифрование
  - `data_collector` - Binance API интеграция
  - `trading_engine` - Торговые стратегии
  - `dashboard_web` - Phoenix LiveView UI
- Настроена конфигурация (dev, test, runtime)

### ✅ Фаза 2: Database Schemas (Completed)
Созданы следующие схемы:
- **User** - Пользователи с Argon2 хешированием паролей
- **ApiCredential** - Зашифрованные API ключи (Cloak)
- **Account** - Binance аккаунты
- **Trade** - История сделок (TimescaleDB hypertable)
- **Order** - Ордера
- **Balance** - Балансы
- **Setting** - Настройки стратегий

### ✅ Фаза 3: Database Migrations (Completed)
Созданы миграции для всех таблиц:
- TimescaleDB extension
- Hypertable для trades с continuous aggregates
- Индексы и constraints
- Foreign keys с правильными cascade policies

### ✅ Фаза 4: Binance Integration (Completed)
**REST API Client:**
- `BinanceClient` - HTTP клиент с HMAC-SHA256 подписями
- `RateLimiter` - Sliding window rate limiting
- Методы: get_account, get_balances, create_order, cancel_order, get_ticker_price

**WebSocket:**
- `BinanceWebSocket` - Real-time streams
- Обработка executionReport, balanceUpdate, ticker, trades
- Phoenix.PubSub broadcasting

**Market Data:**
- `MarketData` - ETS-based cache
- Кеширование цен и тикеров
- Подписка на market events

### ✅ Фаза 5: Trading Engine (Completed)
**Стратегии:**
- `Naive` - Buy-low, sell-high
- `Grid` - Сеточная торговля с автоматической ребалансировкой
- `DCA` - Dollar Cost Averaging

**Core Modules:**
- `Trader` - GenServer для каждого аккаунта
- `OrderManager` - Управление ордерами и синхронизация с БД
- `PositionTracker` - Отслеживание позиций и P&L
- `RiskManager` - Проверка лимитов перед размещением ордеров
- `AccountSupervisor` - DynamicSupervisor для Trader процессов

**Architecture:**
- Registry для Trader процессов
- Phoenix.PubSub для межпроцессной коммуникации
- Один Trader GenServer на аккаунт

### ✅ Фаза 6: Phoenix Dashboard (Completed)
**LiveView Pages:**
- `TradingLive` - Активные сделки
- `PortfolioLive` - Портфель и балансы
- `SettingsLive` - Настройки
- `HistoryLive` - История сделок

**Components:**
- `CoreComponents` - Базовые UI компоненты
- `Layouts` - Root и App layouts
- Routing и navigation

## Как запустить

### Требования
- Elixir 1.14+
- PostgreSQL 15+ с TimescaleDB
- Node.js 18+ (для Phoenix assets)

### Через Docker

```bash
# 1. Запустить PostgreSQL и Redis
make start

# 2. Войти в dev контейнер
docker-compose exec dev bash

# 3. Установить зависимости
mix deps.get

# 4. Настроить БД
cd apps/shared_data
mix ecto.create
mix ecto.migrate
cd ../..

# 5. Запустить сервер
cd apps/dashboard_web
mix phx.server
```

### Локально

```bash
# 1. Установить зависимости
mix deps.get

# 2. Настроить переменные окружения
cp .env.example .env
# Отредактировать .env

# 3. Создать БД
cd apps/shared_data
mix ecto.create
mix ecto.migrate
cd ../..

# 4. Запустить сервер
cd apps/dashboard_web
mix phx.server

# Или из корня
mix phx.server
```

## Переменные окружения

Обязательные:
```bash
BINANCE_API_KEY=your_testnet_api_key
BINANCE_SECRET_KEY=your_testnet_secret
CLOAK_KEY=your_256bit_base64_key
SECRET_KEY_BASE=your_phoenix_secret
DATABASE_URL=postgres://postgres:postgres@localhost/binance_trading_dev
```

## Следующие шаги

### Фаза 7: Аутентификация и безопасность
- [ ] Guardian JWT authentication
- [ ] Login/Register LiveView pages
- [ ] Session management
- [ ] Rate limiting для API endpoints
- [ ] Аудит логирование

### Фаза 8: Тестирование
- [ ] Unit тесты для всех модулей
- [ ] Integration тесты для Binance API
- [ ] LiveView тесты
- [ ] Property-based тесты

### Фаза 9: Документация
- [ ] ExDoc для всех модулей
- [ ] API documentation
- [ ] User guides

### Фаза 10: Production
- [ ] Release configuration
- [ ] Docker production build
- [ ] CI/CD pipeline
- [ ] Monitoring и logging

## Коммиты

Все изменения должны быть закоммичены:

```bash
# Добавить все файлы
git add .

# Коммит
git commit -m "Phase 1-6: Complete Umbrella project implementation
- Initialize umbrella structure with 4 apps
- Add database schemas and migrations
- Implement Binance REST and WebSocket clients
- Add trading strategies (Naive, Grid, DCA)
- Implement Trader GenServer with supervision
- Add Phoenix LiveView dashboard
- Copy skills from master branch"

# Push в ветку verdent
git push origin verdent
```

## Структура файлов

```
binance_system/
├── apps/
│   ├── shared_data/
│   │   ├── lib/
│   │   │   ├── shared_data.ex
│   │   │   ├── shared_data/
│   │   │   │   ├── application.ex
│   │   │   │   ├── repo.ex
│   │   │   │   ├── vault.ex
│   │   │   │   ├── encrypted/binary.ex
│   │   │   │   └── schemas/
│   │   │   │       ├── user.ex
│   │   │   │       ├── api_credential.ex
│   │   │   │       ├── account.ex
│   │   │   │       ├── trade.ex
│   │   │   │       ├── order.ex
│   │   │   │       ├── balance.ex
│   │   │   │       └── setting.ex
│   │   └── priv/repo/migrations/
│   │
│   ├── data_collector/
│   │   └── lib/data_collector/
│   │       ├── application.ex
│   │       ├── binance_client.ex
│   │       ├── binance_websocket.ex
│   │       ├── rate_limiter.ex
│   │       └── market_data.ex
│   │
│   ├── trading_engine/
│   │   └── lib/trading_engine/
│   │       ├── application.ex
│   │       ├── strategy.ex (behaviour)
│   │       ├── trader.ex
│   │       ├── account_supervisor.ex
│   │       ├── order_manager.ex
│   │       ├── position_tracker.ex
│   │       ├── risk_manager.ex
│   │       └── strategies/
│   │           ├── naive.ex
│   │           ├── grid.ex
│   │           └── dca.ex
│   │
│   └── dashboard_web/
│       └── lib/dashboard_web/
│           ├── application.ex
│           ├── endpoint.ex
│           ├── router.ex
│           ├── telemetry.ex
│           ├── live/
│           │   ├── trading_live.ex
│           │   ├── portfolio_live.ex
│           │   ├── settings_live.ex
│           │   └── history_live.ex
│           └── components/
│               ├── core_components.ex
│               └── layouts/
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   └── runtime.exs
│
└── mix.exs
```

## Skills

Все skills скопированы из master:
- `binance-api.md` - Binance API integration
- `ecto-timescale.md` - TimescaleDB with Ecto
- `elixir-otp.md` - OTP patterns
- `elixir-security.md` - Security best practices
- `phoenix-liveview.md` - LiveView components
- `trading-strategies.md` - Trading strategy patterns
- И другие...

## Документация

См. основную документацию:
- `README.md` - Основная документация проекта
- `IMPLEMENTATION_PLAN.md` - Детальный план реализации
- `QUICKSTART.md` - Быстрый старт
- `README_UMBRELLA.md` - Этот файл
- `SKILLS_GUIDE.md` - Руководство по Skills

## Лицензия

MIT
