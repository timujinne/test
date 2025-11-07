# План реализации системы управления криптокошельками Binance

## 📋 Оглавление
1. [Необходимые API ключи и настройки](#необходимые-api-ключи-и-настройки)
2. [Технологический стек](#технологический-стек)
3. [Этапы реализации](#этапы-реализации)
4. [Структура проекта](#структура-проекта)
5. [Подключение skills](#подключение-skills)

---

## 🔑 Необходимые API ключи и настройки

### 1. Binance API Credentials

**Где получить:**
- Перейти на [Binance API Management](https://www.binance.com/en/my/settings/api-management)
- Создать новый API ключ
- Включить необходимые разрешения

**Требуемые разрешения:**
```
✅ Enable Reading (обязательно)
✅ Enable Spot & Margin Trading (для торговли)
✅ Enable Futures (опционально, для фьючерсов)
❌ Enable Withdrawals (НЕ рекомендуется для безопасности)
```

**Переменные окружения:**
```bash
BINANCE_API_KEY=your_api_key_here
BINANCE_SECRET_KEY=your_secret_key_here
BINANCE_BASE_URL=https://api.binance.com
BINANCE_WS_URL=wss://stream.binance.com:9443
```

**⚠️ ВАЖНО:**
- Используйте Testnet для разработки: https://testnet.binance.vision/
- Никогда не коммитьте ключи в git
- Используйте IP whitelist для дополнительной безопасности

### 2. Ключ шифрования (Cloak)

**Генерация 256-bit ключа:**
```bash
# В Elixir console (iex)
iex> 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
# Пример вывода: "tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8="
```

**Переменная окружения:**
```bash
CLOAK_KEY=your_generated_base64_key_here
```

### 3. Database Configuration

**PostgreSQL + TimescaleDB:**
```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/binance_trading_dev
DATABASE_POOL_SIZE=10

# Для production
DATABASE_SSL=true
DATABASE_SSL_VERIFY=verify_none
```

### 4. Redis Configuration (опционально)

**Для кеширования и распределённого PubSub:**
```bash
REDIS_URL=redis://localhost:6379/0
REDIS_POOL_SIZE=5
```

### 5. Phoenix Secret Key Base

**Генерация:**
```bash
mix phx.gen.secret
# Пример: "VGhpcyBpcyBhIHNlY3JldCBrZXkgZm9yIHRoZSBhcHBsaWNhdGlvbg=="
```

**Переменная окружения:**
```bash
SECRET_KEY_BASE=your_secret_key_base_here
```

### 6. Полный .env файл

```bash
# Binance API
BINANCE_API_KEY=your_api_key
BINANCE_SECRET_KEY=your_secret_key
BINANCE_BASE_URL=https://testnet.binance.vision
BINANCE_WS_URL=wss://testnet.binance.vision/ws

# Security
CLOAK_KEY=your_256bit_base64_encoded_key
SECRET_KEY_BASE=your_phoenix_secret_key

# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/binance_trading_dev
DATABASE_POOL_SIZE=10

# Redis (optional)
REDIS_URL=redis://localhost:6379/0

# Application
PHX_HOST=localhost
PORT=4000
MIX_ENV=dev

# Monitoring (optional)
ENABLE_TELEMETRY=true
GRAFANA_API_KEY=your_grafana_key
```

---

## 🛠 Технологический стек

### Backend
- **Elixir** 1.14+ (язык программирования)
- **Phoenix** 1.7+ (web framework)
- **Phoenix LiveView** (real-time UI)
- **Ecto** (database wrapper)
- **WebSockex** (WebSocket client)

### Database
- **PostgreSQL** 15+ (основная БД)
- **TimescaleDB** (time-series данные)

### Кеширование
- **ETS** (встроенный in-memory)
- **Nebulex** (кеш-библиотека)
- **Redis** (опционально, для распределённого кеша)

### Безопасность
- **Cloak** (шифрование в БД)
- **Argon2** (хеширование паролей)
- **Guardian** (JWT аутентификация)

### Мониторинг
- **Telemetry** (метрики)
- **Phoenix LiveDashboard** (real-time мониторинг)
- **Logger** (логирование)

### Библиотеки для Binance
- **binance** (dvcrn/binance.ex) - основной клиент
- **jason** - JSON парсинг
- **decimal** - точные вычисления для денег

---

## 📝 Этапы реализации

### Этап 1: Настройка окружения (1-2 дня)

#### 1.1 Установка зависимостей

**Linux (Ubuntu/Debian):**
```bash
# Добавить Erlang Solutions repo
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update

# Установить Erlang и Elixir
sudo apt-get install -y elixir erlang-dev erlang-xmerl

# Установить PostgreSQL с TimescaleDB
sudo apt-get install -y postgresql postgresql-contrib
sudo add-apt-repository ppa:timescale/timescaledb-ppa
sudo apt-get update
sudo apt-get install -y timescaledb-postgresql-15

# Установить Phoenix
mix local.hex --force
mix archive.install hex phx_new --force

# Установить Node.js (для assets)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```

**Docker (рекомендуется):**
```yaml
# docker-compose.yml создастся на следующем этапе
```

#### 1.2 Проверка установки
```bash
elixir --version
# Erlang/OTP 25 [erts-13.0]
# Elixir 1.14.2

mix --version
# Mix 1.14.2

psql --version
# psql (PostgreSQL) 15.0
```

---

### Этап 2: Создание Umbrella проекта (1 день)

#### 2.1 Создание базовой структуры

```bash
# Создать umbrella проект
mix new binance_system --umbrella
cd binance_system

# Создать приложения
cd apps

# 1. Shared Data (общие схемы и БД)
mix new shared_data --sup

# 2. Data Collector (сбор рыночных данных)
mix new data_collector --sup

# 3. Trading Engine (торговая логика)
mix new trading_engine --sup

# 4. Dashboard Web (Phoenix интерфейс)
cd ..
mix phx.new apps/dashboard_web --no-ecto

cd ..
```

#### 2.2 Настройка зависимостей

**Корневой mix.exs:**
```elixir
defmodule BinanceSystem.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
```

#### 2.3 Настройка конфигурации

**config/config.exs:**
```elixir
import Config

config :binance_system,
  ecto_repos: [SharedData.Repo]

config :shared_data,
  ecto_repos: [SharedData.Repo]

# Phoenix PubSub для межсервисной коммуникации
config :binance_system, BinanceSystem.PubSub,
  name: BinanceSystem.PubSub,
  adapter: Phoenix.PubSub.PG2

# Импортировать конфиги приложений
import_config "../apps/*/config/config.exs"
import_config "#{config_env()}.exs"
```

**config/runtime.exs:**
```elixir
import Config

if config_env() == :prod do
  # Binance API
  config :binance,
    api_key: System.fetch_env!("BINANCE_API_KEY"),
    secret_key: System.fetch_env!("BINANCE_SECRET_KEY"),
    end_point: System.get_env("BINANCE_BASE_URL", "https://api.binance.com")

  # Database
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  config :shared_data, SharedData.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10")

  # Cloak encryption
  config :shared_data, SharedData.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1",
        key: Base.decode64!(System.fetch_env!("CLOAK_KEY")),
        iv_length: 12
      }
    ]

  # Phoenix
  config :dashboard_web, DashboardWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
```

---

### Этап 3: База данных и схемы (2-3 дня)

#### 3.1 Настройка SharedData

**apps/shared_data/mix.exs:**
```elixir
defp deps do
  [
    {:ecto_sql, "~> 3.10"},
    {:postgrex, "~> 0.17"},
    {:jason, "~> 1.4"},
    {:cloak_ecto, "~> 1.2"},
    {:decimal, "~> 2.0"}
  ]
end
```

#### 3.2 Создание схем

**Основные схемы:**
- `User` - пользователи системы
- `ApiCredential` - зашифрованные API ключи
- `Trade` - история торгов (TimescaleDB)
- `Order` - ордера
- `Balance` - балансы аккаунтов
- `Setting` - настройки торговли

#### 3.3 Миграции

```bash
cd apps/shared_data
mix ecto.gen.migration create_users
mix ecto.gen.migration create_api_credentials
mix ecto.gen.migration create_trades_hypertable
mix ecto.gen.migration create_orders
```

---

### Этап 4: Интеграция с Binance API (3-4 дня)

#### 4.1 Настройка клиента

**apps/data_collector/mix.exs:**
```elixir
defp deps do
  [
    {:binance, "~> 2.0"},
    {:websockex, "~> 0.4"},
    {:jason, "~> 1.4"},
    {:shared_data, in_umbrella: true},
    {:phoenix_pubsub, "~> 2.1"}
  ]
end
```

#### 4.2 Модули для реализации:

1. **BinanceClient** - HTTP клиент с rate limiting
2. **BinanceWebSocket** - WebSocket стримы
3. **MarketData** - агрегация рыночных данных
4. **OrderBook** - стакан ордеров
5. **RateLimiter** - контроль лимитов

---

### Этап 5: Trading Engine (4-5 дней)

#### 5.1 Архитектура

```
TradingEngine.Application
├── AccountSupervisor (DynamicSupervisor)
│   └── Trader процессы (по одному на аккаунт)
├── OrderManager
├── PositionTracker
├── RiskManager
└── StrategyRegistry
```

#### 5.2 Стратегии торговли:

1. **Naive** - простая buy-low, sell-high
2. **Grid** - сеточная торговля
3. **DCA** - dollar cost averaging
4. **Custom** - пользовательские стратегии

---

### Этап 6: Phoenix Dashboard (3-4 дня)

#### 6.1 Компоненты LiveView:

1. **TradingLive** - активные сделки
2. **PortfolioLive** - балансы и позиции
3. **SettingsLive** - настройки стратегий
4. **HistoryLive** - история торгов
5. **MonitoringLive** - мониторинг системы

#### 6.2 Phoenix Channels:

- `market:*` - рыночные данные
- `orders:user_id` - обновления ордеров
- `portfolio:user_id` - изменения баланса

---

### Этап 7: Безопасность и мониторинг (2-3 дня)

#### 7.1 Безопасность:

- ✅ Шифрование API ключей (Cloak)
- ✅ JWT аутентификация (Guardian)
- ✅ Rate limiting
- ✅ Аудит логирование
- ✅ IP whitelisting

#### 7.2 Мониторинг:

- ✅ Phoenix LiveDashboard
- ✅ Telemetry метрики
- ✅ Логирование всех операций
- ✅ Алерты на критические события

---

### Этап 8: Docker и Deployment (2 дня)

#### 8.1 Docker Compose:

```yaml
services:
  postgres:
    image: timescale/timescaledb:latest-pg15

  redis:
    image: redis:7-alpine

  app:
    build: .
    depends_on:
      - postgres
      - redis
```

---

## 📁 Финальная структура проекта

```
binance_system/
├── apps/
│   ├── shared_data/              # Общие данные
│   │   ├── lib/
│   │   │   ├── shared_data/
│   │   │   │   ├── schemas/      # Ecto схемы
│   │   │   │   ├── repo.ex
│   │   │   │   └── vault.ex      # Cloak vault
│   │   │   └── shared_data.ex
│   │   ├── priv/repo/migrations/
│   │   └── mix.exs
│   │
│   ├── data_collector/           # Сбор данных
│   │   ├── lib/
│   │   │   ├── data_collector/
│   │   │   │   ├── binance_client.ex
│   │   │   │   ├── binance_websocket.ex
│   │   │   │   ├── market_data.ex
│   │   │   │   ├── order_book.ex
│   │   │   │   └── rate_limiter.ex
│   │   │   └── data_collector.ex
│   │   └── mix.exs
│   │
│   ├── trading_engine/           # Торговая логика
│   │   ├── lib/
│   │   │   ├── trading_engine/
│   │   │   │   ├── strategies/
│   │   │   │   │   ├── naive.ex
│   │   │   │   │   └── grid.ex
│   │   │   │   ├── account_supervisor.ex
│   │   │   │   ├── trader.ex
│   │   │   │   ├── order_manager.ex
│   │   │   │   ├── position_tracker.ex
│   │   │   │   └── risk_manager.ex
│   │   │   └── trading_engine.ex
│   │   └── mix.exs
│   │
│   └── dashboard_web/            # Phoenix UI
│       ├── lib/
│       │   ├── dashboard_web/
│       │   │   ├── channels/
│       │   │   ├── controllers/
│       │   │   ├── live/
│       │   │   │   ├── trading_live.ex
│       │   │   │   ├── portfolio_live.ex
│       │   │   │   └── settings_live.ex
│       │   │   ├── components/
│       │   │   └── endpoint.ex
│       │   └── dashboard_web.ex
│       ├── assets/
│       └── mix.exs
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
│
├── .env.example
├── .gitignore
├── docker-compose.yml
├── Dockerfile
├── mix.exs
└── README.md
```

---

## 🎯 Подключение Skills

В Claude Code можно использовать существующие skills для ускорения разработки:

### Доступные skills:

1. **session-start-hook** - настройка хуков для проекта

### Как использовать skills:

```bash
# Просмотр доступных skills
/help skills

# Использование skill
/skill session-start-hook
```

### Создание собственных skills:

Можно создать custom skills для:
- Генерации Elixir модулей
- Создания миграций БД
- Настройки тестов
- Деплоя

**Пример custom skill (.claude/skills/elixir_module.md):**
```markdown
---
name: elixir-module
description: Generate Elixir GenServer module with supervision
---

Generate a new Elixir GenServer module with:
- Supervision setup
- Init callback
- Handle_call/cast/info
- Tests
```

---

## ⏱ Временная оценка

| Этап | Описание | Время |
|------|----------|-------|
| 1 | Настройка окружения | 1-2 дня |
| 2 | Создание umbrella проекта | 1 день |
| 3 | База данных и схемы | 2-3 дня |
| 4 | Интеграция Binance API | 3-4 дня |
| 5 | Trading Engine | 4-5 дней |
| 6 | Phoenix Dashboard | 3-4 дня |
| 7 | Безопасность и мониторинг | 2-3 дня |
| 8 | Docker и Deployment | 2 дня |
| **ИТОГО** | | **18-28 дней** |

---

## 📚 Ресурсы для изучения

### Документация:
- [Elixir Lang](https://elixir-lang.org/)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Binance API Docs](https://binance-docs.github.io/apidocs/)

### Книги:
- "Hands-on Elixir & OTP: Cryptocurrency trading bot" - Kamil Skowron
- "Programming Phoenix LiveView" - Bruce Tate
- "Designing Elixir Systems with OTP" - James Edward Gray

### GitHub репозитории:
- [fremantle-industries/tai](https://github.com/fremantle-industries/tai)
- [fremantle-industries/prop](https://github.com/fremantle-industries/prop)
- [Cinderella-Man/hands-on-elixir](https://github.com/Cinderella-Man/hands-on-elixir-and-otp-cryptocurrency-trading-bot)

---

## ✅ Чеклист перед началом

- [ ] Создан аккаунт на Binance Testnet
- [ ] Получены API ключи (testnet)
- [ ] Сгенерирован ключ шифрования (Cloak)
- [ ] Установлены Elixir, PostgreSQL
- [ ] Создан .env файл с переменными
- [ ] Настроен Docker (опционально)
- [ ] Прочитана документация Binance API
- [ ] Изучены основы Elixir/Phoenix

---

## 🚀 Быстрый старт

```bash
# 1. Клонировать или создать репозиторий
git clone <your-repo>
cd binance_system

# 2. Скопировать .env.example в .env
cp .env.example .env
# Отредактировать .env с вашими ключами

# 3. Установить зависимости
mix deps.get

# 4. Создать и мигрировать БД
mix ecto.setup

# 5. Запустить приложение
mix phx.server

# Открыть http://localhost:4000
```

---

## 📞 Следующие шаги

1. **Подтвердите наличие API ключей Binance**
2. **Выберите способ установки** (локально или Docker)
3. **Сообщите о готовности начать** разработку

Готов приступить к реализации! Какой этап начнём первым? 🚀
