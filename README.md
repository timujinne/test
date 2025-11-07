# 🚀 Binance Trading System - Система управления криптокошельками

<div align="center">

![Elixir](https://img.shields.io/badge/Elixir-1.14+-purple?logo=elixir)
![Phoenix](https://img.shields.io/badge/Phoenix-1.7+-orange?logo=phoenix-framework)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-blue?logo=postgresql)
![License](https://img.shields.io/badge/license-MIT-green)

*Production-ready система для управления множественными Binance аккаунтами с использованием Elixir/Phoenix*

[Документация](#документация) • [Быстрый старт](#быстрый-старт) • [Архитектура](#архитектура) • [FAQ](#faq)

</div>

---

## 📋 Содержание

- [Возможности](#возможности)
- [Архитектура](#архитектура)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Конфигурация](#конфигурация)
- [Разработка](#разработка)
- [Тестирование](#тестирование)
- [Deployment](#deployment)
- [Безопасность](#безопасность)
- [Документация](#документация)
- [Contributing](#contributing)
- [License](#license)

---

## ✨ Возможности

### 🏗 Архитектурные преимущества
- **Microservices Architecture** через Umbrella Projects
- **Fault Tolerance** с OTP supervision trees
- **Real-time Updates** через Phoenix LiveView и Channels
- **Горизонтальное масштабирование** благодаря BEAM VM
- **Изоляция процессов** - один GenServer на аккаунт

### 💹 Торговые функции
- ✅ Управление множественными Binance аккаунтами (через Sub-accounts)
- ✅ Real-time мониторинг рыночных данных
- ✅ Автоматические торговые стратегии (Naive, Grid, DCA)
- ✅ Risk management и stop-loss механизмы
- ✅ Портфельный трекинг и P&L расчёт
- ✅ Исторические данные и аналитика
- ✅ Paper trading режим для тестирования

### 🔒 Безопасность
- ✅ AES-256-GCM шифрование API ключей в БД
- ✅ JWT аутентификация
- ✅ Rate limiting защита
- ✅ Аудит логирование всех операций
- ✅ IP whitelisting для API ключей

### 📊 Мониторинг и аналитика
- ✅ Phoenix LiveDashboard для real-time метрик
- ✅ TimescaleDB для эффективного хранения time-series данных
- ✅ Continuous aggregates для предрасчёта статистики
- ✅ Grafana интеграция (опционально)
- ✅ Telemetry метрики

---

## 🏛 Архитектура

```
binance_system/
├── apps/
│   ├── shared_data/         # 💾 Общие схемы БД и Ecto Repo
│   ├── data_collector/      # 📡 Сбор данных от Binance API/WebSocket
│   ├── trading_engine/      # ⚙️ Торговая логика и стратегии
│   └── dashboard_web/       # 🖥 Phoenix LiveView интерфейс
└── config/                  # ⚙️ Конфигурация
```

### Стек технологий

| Компонент | Технология |
|-----------|------------|
| **Language** | Elixir 1.14+ |
| **Framework** | Phoenix 1.7+ |
| **Database** | PostgreSQL 15 + TimescaleDB |
| **Cache** | ETS + Redis |
| **WebSocket** | Phoenix Channels |
| **API Client** | dvcrn/binance.ex |
| **Encryption** | Cloak |
| **Monitoring** | Telemetry + LiveDashboard |

---

## 📦 Требования

### Обязательные
- **Elixir** 1.14+ и **Erlang/OTP** 25+
- **PostgreSQL** 15+
- **Node.js** 18+ (для Phoenix assets)

### Опциональные
- **Docker** и **Docker Compose** (рекомендуется)
- **Redis** 7+ (для распределённого кеша)
- **TimescaleDB** (расширение для PostgreSQL)

### Binance API
- Аккаунт на [Binance](https://www.binance.com)
- API ключи с необходимыми разрешениями
- **Для тестирования**: используйте [Binance Testnet](https://testnet.binance.vision/)

---

## 🚀 Быстрый старт

### Способ 1: Docker (рекомендуется)

```bash
# 1. Клонировать репозиторий
git clone <your-repo-url>
cd binance_system

# 2. Настроить переменные окружения
cp .env.example .env
# Отредактируйте .env с вашими API ключами

# 3. Запустить сервисы
make start

# 4. Создать umbrella проект (первый раз)
mix new binance_system --umbrella
cd binance_system
mix deps.get

# 5. Настроить БД
make db-create
make db-migrate

# 6. Запустить приложение
make server

# Открыть http://localhost:4000
```

### Способ 2: Локальная установка

```bash
# 1. Установить Elixir и зависимости
# Ubuntu/Debian:
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y elixir erlang-dev postgresql-15

# 2. Установить Phoenix
mix local.hex --force
mix archive.install hex phx_new --force

# 3. Настроить проект
cp .env.example .env
# Отредактируйте .env

# 4. Установить зависимости
mix deps.get

# 5. Настроить БД
mix ecto.create
mix ecto.migrate

# 6. Запустить сервер
mix phx.server
```

---

## ⚙️ Конфигурация

### Получение Binance API ключей

#### Testnet (для разработки)
1. Перейти на https://testnet.binance.vision/
2. Войти через GitHub
3. Получить API Key и Secret Key
4. Использовать testnet endpoints:
   - REST: `https://testnet.binance.vision`
   - WebSocket: `wss://testnet.binance.vision/ws`

#### Production
1. Перейти на https://www.binance.com/en/my/settings/api-management
2. Создать новый API ключ
3. Настроить разрешения:
   - ✅ Enable Reading
   - ✅ Enable Spot & Margin Trading
   - ❌ Enable Withdrawals (НЕ рекомендуется)
4. Настроить IP whitelist для безопасности

### Генерация ключа шифрования

```bash
# Способ 1: через Make
make gen-secret

# Способ 2: через IEx
iex -S mix
iex> 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
```

### Структура .env файла

Скопируйте `.env.example` в `.env` и заполните:

```bash
# Binance API
BINANCE_API_KEY=your_api_key
BINANCE_SECRET_KEY=your_secret_key
BINANCE_BASE_URL=https://testnet.binance.vision

# Security
CLOAK_KEY=your_base64_encoded_key
SECRET_KEY_BASE=your_phoenix_secret

# Database
DATABASE_URL=postgres://postgres:postgres@localhost:5432/binance_trading_dev
```

Полный пример см. в [.env.example](.env.example)

---

## 💻 Разработка

### Полезные команды

```bash
# Запуск сервера
make server              # Запустить Phoenix сервер
make server-iex          # С IEx консолью

# База данных
make db-create           # Создать БД
make db-migrate          # Миграции
make db-reset            # Пересоздать БД
make db-seed             # Заполнить тестовыми данными

# Тестирование
make test                # Запустить тесты
make test-watch          # Тесты в watch режиме
make check               # Полная проверка (format + credo + tests)

# Docker
make start               # Запустить контейнеры
make stop                # Остановить
make logs                # Смотреть логи
make logs-app            # Логи приложения

# Код
make format              # Форматировать код
make credo               # Проверка качества
make dialyzer            # Статический анализ

# Мониторинг
make start-monitoring    # Запустить с Grafana
make open-grafana        # Открыть Grafana UI
make open-pgadmin        # Открыть pgAdmin
```

Полный список команд: `make help`

### Структура Umbrella проекта

После создания проекта структура будет:

```
binance_system/
├── apps/
│   ├── shared_data/              # Общие данные
│   │   ├── lib/shared_data/
│   │   │   ├── schemas/          # User, ApiCredential, Trade, etc.
│   │   │   ├── repo.ex
│   │   │   └── vault.ex          # Cloak encryption
│   │   └── priv/repo/migrations/
│   │
│   ├── data_collector/           # Binance интеграция
│   │   └── lib/data_collector/
│   │       ├── binance_client.ex
│   │       ├── binance_websocket.ex
│   │       ├── market_data.ex
│   │       └── rate_limiter.ex
│   │
│   ├── trading_engine/           # Торговая логика
│   │   └── lib/trading_engine/
│   │       ├── strategies/       # Naive, Grid, DCA
│   │       ├── trader.ex
│   │       ├── order_manager.ex
│   │       └── risk_manager.ex
│   │
│   └── dashboard_web/            # Phoenix UI
│       └── lib/dashboard_web/
│           ├── live/             # LiveView компоненты
│           ├── channels/         # WebSocket каналы
│           └── controllers/
│
├── config/
│   ├── config.exs                # Base config
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs               # Runtime секреты
│
├── .env.example
├── docker-compose.yml
├── Makefile
└── README.md
```

---

## 🧪 Тестирование

```bash
# Запустить все тесты
mix test

# С coverage
mix test --cover

# Конкретный файл
mix test test/trading_engine/strategies/naive_test.exs

# С watch режимом
mix test.watch
```

### Типы тестов

- **Unit tests** - изолированные тесты модулей
- **Integration tests** - тесты взаимодействия компонентов
- **Property-based tests** - с использованием StreamData
- **Feature tests** - end-to-end тесты через LiveView

---

## 🚢 Deployment

### Production Build

```bash
# Сборка release
MIX_ENV=prod mix release

# Запуск
_build/prod/rel/binance_system/bin/binance_system start

# Daemon режим
_build/prod/rel/binance_system/bin/binance_system daemon
```

### Docker Production

```bash
# Сборка образа
docker build -t binance-system:latest .

# Запуск
docker run -d \
  --name binance-system \
  -p 4000:4000 \
  --env-file .env.prod \
  binance-system:latest
```

### Переменные окружения для Production

```bash
# Обязательные
BINANCE_API_KEY=xxx
BINANCE_SECRET_KEY=xxx
SECRET_KEY_BASE=xxx
CLOAK_KEY=xxx
DATABASE_URL=postgres://...

# Рекомендуемые
DATABASE_POOL_SIZE=20
PORT=4000
PHX_HOST=yourdomain.com
ENABLE_SSL=true
```

---

## 🔒 Безопасность

### ⚠️ ВАЖНО: Мультиаккаунтинг

**Условия использования Binance** (Section 20.1.l) запрещают множественные личные аккаунты.

**ЛЕГАЛЬНЫЕ способы:**
1. **Sub-accounts** - для VIP1+ пользователей (до 200 sub-аккаунтов)
2. **Корпоративные аккаунты** - отдельные юридические лица

### Лучшие практики

✅ **Делайте:**
- Используйте testnet для разработки
- Храните ключи в переменных окружения
- Настройте IP whitelist для API ключей
- Регулярно ротируйте API ключи
- Включите 2FA на Binance аккаунте
- Логируйте все операции с деньгами
- Используйте paper trading перед реальной торговлей

❌ **Не делайте:**
- Коммитить ключи в git
- Давать API ключам права на вывод средств
- Использовать production ключи в development
- Создавать множественные личные аккаунты
- Игнорировать rate limits

---

## 📚 Документация

### Полное руководство
- [📘 IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - Детальный план реализации
- [🔑 API Keys Setup](docs/api-keys-setup.md) - Настройка API ключей
- [🏗 Architecture Guide](docs/architecture.md) - Архитектурные решения
- [🔒 Security Best Practices](docs/security.md) - Безопасность
- [📈 Trading Strategies](docs/strategies.md) - Торговые стратегии

### Внешние ресурсы
- [Elixir Documentation](https://elixir-lang.org/docs.html)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Binance API Docs](https://binance-docs.github.io/apidocs/)
- [Книга: Hands-on Elixir & OTP](https://pragprog.com/titles/krlexir/)

---

## 🤝 Contributing

Мы приветствуем ваш вклад! Пожалуйста:

1. Fork проекта
2. Создайте feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit изменения (`git commit -m 'Add some AmazingFeature'`)
4. Push в branch (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

### Правила
- Следуйте [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Добавляйте тесты для новых функций
- Обновляйте документацию
- Проверьте `make check` перед commit

---

## 📝 License

Этот проект лицензирован под MIT License - см. файл [LICENSE](LICENSE)

---

## 👥 Авторы

- **Ваше имя** - *Initial work*

---

## 🙏 Благодарности

- [fremantle-industries/tai](https://github.com/fremantle-industries/tai) - за вдохновение в архитектуре
- [dvcrn/binance.ex](https://github.com/dvcrn/binance.ex) - отличный Binance клиент
- [Cinderella-Man/hands-on-elixir](https://github.com/Cinderella-Man/hands-on-elixir-and-otp-cryptocurrency-trading-bot) - за обучающие примеры

---

## 📞 Контакты и поддержка

- 📧 Email: your-email@example.com
- 💬 Telegram: @yourusername
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/binance_system/issues)

---

## ⚠️ Disclaimer

Эта система предоставляется "как есть" без каких-либо гарантий. Торговля криптовалютами несёт высокие риски. Используйте на свой страх и риск. Авторы не несут ответственности за финансовые потери.

**Всегда тестируйте стратегии в paper trading режиме перед использованием реальных средств!**

---

<div align="center">

Made with ❤️ using Elixir and Phoenix

⭐ Если проект был полезен, поставьте звезду!

</div>
