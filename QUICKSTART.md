# ⚡ Быстрый старт - Binance Trading System

## 📋 Предварительные требования

Убедитесь, что установлено:
- [ ] Docker и Docker Compose
- [ ] Git
- [ ] Текстовый редактор (VS Code, Vim, etc.)

Опционально (для локальной разработки без Docker):
- [ ] Elixir 1.14+
- [ ] PostgreSQL 15+
- [ ] Node.js 18+

---

## 🚀 Шаг 1: Получение API ключей Binance Testnet

### 1.1 Регистрация в Testnet

1. Перейти на https://testnet.binance.vision/
2. Нажать **"Login with GitHub"**
3. Авторизоваться через GitHub

### 1.2 Генерация API ключей

1. В правом верхнем углу нажать на иконку профиля
2. Выбрать **"API Keys"**
3. Нажать **"Generate HMAC_SHA256 Key"**
4. Скопировать:
   - **API Key** (например: `XMEfQECq2rnk7vZ8qVvvnT7dJ3Qw4Mx0qzHq3wZ8qVvvnT7dJ3Qw4Mx0`)
   - **Secret Key** (например: `BtcethxrpLTCcoinexchangeSecreTKeyxxx`)

⚠️ **ВАЖНО**: Secret Key показывается только один раз! Сохраните его в безопасном месте.

### 1.3 Получение тестовых средств

1. Перейти на https://testnet.binance.vision/faucet
2. Выбрать криптовалюту (BTC, ETH, USDT)
3. Нажать **"Get Test Funds"**
4. Средства появятся в течение нескольких секунд

---

## 🔧 Шаг 2: Настройка проекта

### 2.1 Клонирование репозитория

```bash
git clone https://github.com/yourusername/binance_system.git
cd binance_system
```

### 2.2 Создание .env файла

```bash
# Скопировать шаблон
cp .env.example .env
```

### 2.3 Редактирование .env

Откройте `.env` в текстовом редакторе и вставьте ваши ключи:

```bash
# === BINANCE API CREDENTIALS ===
BINANCE_API_KEY=ВСТАВЬТЕ_СЮДА_ВАШ_API_KEY
BINANCE_SECRET_KEY=ВСТАВЬТЕ_СЮДА_ВАШ_SECRET_KEY

# Testnet URLs (НЕ изменяйте)
BINANCE_BASE_URL=https://testnet.binance.vision
BINANCE_WS_URL=wss://testnet.binance.vision/ws
```

### 2.4 Генерация ключа шифрования

**Способ 1: Онлайн генератор**
```bash
# Сгенерировать 32 байта в base64
openssl rand -base64 32
```

Результат будет примерно:
```
tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8=
```

Вставьте в `.env`:
```bash
CLOAK_KEY=tJq/RQzw8QV9dJFELmKwEiCq0lTFqe0y9fKDnSdmUm8=
```

**Способ 2: Python генератор**
```bash
python3 -c "import os, base64; print(base64.b64encode(os.urandom(32)).decode())"
```

**Способ 3: Node.js генератор**
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

### 2.5 Генерация Phoenix secret

```bash
# Если Elixir установлен локально:
mix phx.gen.secret

# Или используйте онлайн генератор случайных строк (64+ символа)
openssl rand -base64 48
```

Вставьте в `.env`:
```bash
SECRET_KEY_BASE=ВАША_СГЕНЕРИРОВАННАЯ_СТРОКА
```

---

## 🐳 Шаг 3: Запуск с Docker (рекомендуется)

### 3.1 Запуск базовых сервисов

```bash
# Запустить PostgreSQL и Redis
make start

# Проверить статус
make ps
```

Должны увидеть:
```
       Name                     Command               State           Ports
-------------------------------------------------------------------------------------
binance_postgres      docker-entrypoint.sh postgres    Up      0.0.0.0:5432->5432/tcp
binance_redis         redis-server --appendonly yes    Up      0.0.0.0:6379->6379/tcp
```

### 3.2 Просмотр логов

```bash
# Логи всех сервисов
make logs

# Только PostgreSQL
make logs-postgres

# Только Redis
make logs-redis
```

---

## 📦 Шаг 4: Создание Elixir проекта

### 4.1 Установка Elixir (если не установлен)

**Ubuntu/Debian:**
```bash
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y elixir erlang-dev
```

**macOS:**
```bash
brew install elixir
```

**Windows:**
- Скачать инсталлятор с https://elixir-lang.org/install.html

### 4.2 Установка Phoenix

```bash
mix local.hex --force
mix archive.install hex phx_new --force
```

### 4.3 Создание umbrella проекта

```bash
# Создать базовую структуру
mix new binance_system --umbrella
cd binance_system

# Перейти в apps
cd apps

# Создать приложения
mix new shared_data --sup
mix new data_collector --sup
mix new trading_engine --sup

# Вернуться в корень и создать Phoenix app
cd ..
mix phx.new apps/dashboard_web --no-ecto
```

При создании Phoenix app выберите:
```
Fetch and install dependencies? [Yn] Y
```

### 4.4 Структура после создания

```
binance_system/
├── apps/
│   ├── shared_data/       ✅ Создано
│   ├── data_collector/    ✅ Создано
│   ├── trading_engine/    ✅ Создано
│   └── dashboard_web/     ✅ Создано
├── config/
└── mix.exs
```

---

## 🗄 Шаг 5: Настройка базы данных

### 5.1 Добавление зависимостей

Редактируйте `apps/shared_data/mix.exs`:

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

### 5.2 Установка зависимостей

```bash
cd binance_system
mix deps.get
```

### 5.3 Настройка Repo

Создайте `apps/shared_data/lib/shared_data/repo.ex`:

```elixir
defmodule SharedData.Repo do
  use Ecto.Repo,
    otp_app: :shared_data,
    adapter: Ecto.Adapters.Postgres
end
```

### 5.4 Настройка конфигурации

Редактируйте `config/config.exs`:

```elixir
import Config

# Repo configuration
config :shared_data,
  ecto_repos: [SharedData.Repo]

config :shared_data, SharedData.Repo,
  database: "binance_trading_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432

# Import environment specific config
import_config "#{config_env()}.exs"
```

### 5.5 Создание базы данных

```bash
cd binance_system
mix ecto.create -r SharedData.Repo
```

Должны увидеть:
```
The database for SharedData.Repo has been created
```

---

## 🎨 Шаг 6: Запуск Phoenix сервера

### 6.1 Установка Node.js зависимостей

```bash
cd apps/dashboard_web/assets
npm install
cd ../../..
```

### 6.2 Запуск сервера

```bash
cd apps/dashboard_web
mix phx.server
```

Или с IEx:
```bash
iex -S mix phx.server
```

### 6.3 Проверка

Откройте браузер:
```
http://localhost:4000
```

Должны увидеть стандартную страницу Phoenix! 🎉

---

## ✅ Шаг 7: Проверка интеграции с Binance

### 7.1 Добавление Binance клиента

Редактируйте `apps/data_collector/mix.exs`:

```elixir
defp deps do
  [
    {:binance, "~> 2.0"},
    {:jason, "~> 1.4"},
    {:httpoison, "~> 2.0"}
  ]
end
```

Установите:
```bash
cd binance_system
mix deps.get
```

### 7.2 Тест подключения

Запустите IEx:
```bash
iex -S mix
```

В консоли выполните:
```elixir
# Настроить ключи (используйте ваши реальные ключи)
Application.put_env(:binance, :api_key, "YOUR_API_KEY")
Application.put_env(:binance, :secret_key, "YOUR_SECRET_KEY")
Application.put_env(:binance, :end_point, "https://testnet.binance.vision")

# Проверить подключение
{:ok, account} = Binance.get_account()

# Должны увидеть ваши балансы
IO.inspect(account.balances, label: "Balances")
```

Успешный результат:
```elixir
Balances: [
  %{asset: "BTC", free: "10.00000000", locked: "0.00000000"},
  %{asset: "ETH", free: "100.00000000", locked: "0.00000000"},
  %{asset: "USDT", free: "10000.00000000", locked: "0.00000000"}
]
```

---

## 📊 Опционально: Инструменты мониторинга

### Запуск с Grafana и Prometheus

```bash
make start-monitoring
```

### Запуск pgAdmin и Redis Commander

```bash
make start-tools
```

### Доступ к инструментам

```bash
# Открыть Grafana (admin/admin)
make open-grafana
# http://localhost:3000

# Открыть pgAdmin (admin@admin.com/admin)
make open-pgadmin
# http://localhost:5050

# Открыть Redis Commander
make open-redis-commander
# http://localhost:8081
```

---

## 🎯 Следующие шаги

После успешного запуска, следуйте детальному плану:

1. 📖 Прочитайте [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
2. 🏗 Создайте схемы базы данных (User, ApiCredential, Trade)
3. 🔌 Реализуйте WebSocket интеграцию с Binance
4. ⚙️ Разработайте торговый движок
5. 🎨 Создайте LiveView dashboard
6. 🧪 Напишите тесты
7. 🚀 Deploy в production

---

## 🆘 Troubleshooting

### Проблема: База данных не подключается

```bash
# Проверить статус PostgreSQL
docker-compose ps postgres

# Перезапустить
make restart

# Проверить логи
make logs-postgres
```

### Проблема: Port 4000 уже занят

```bash
# Найти процесс
lsof -i :4000

# Убить процесс
kill -9 PID

# Или использовать другой порт
PORT=4001 mix phx.server
```

### Проблема: Ошибка при mix deps.get

```bash
# Очистить зависимости
mix deps.clean --all

# Переустановить
mix deps.get
```

### Проблема: Binance API возвращает ошибку

**429 Too Many Requests:**
- Вы превысили rate limit
- Подождите 1 минуту и попробуйте снова

**401 Unauthorized:**
- Проверьте API ключи в .env
- Убедитесь, что используете testnet URLs

**-1021 Timestamp error:**
- Синхронизируйте системное время
- Ubuntu: `sudo ntpdate -s time.nist.gov`

---

## 📞 Получить помощь

- 📖 [Полная документация](README.md)
- 📘 [План реализации](IMPLEMENTATION_PLAN.md)
- 🐛 [Сообщить о проблеме](https://github.com/yourusername/binance_system/issues)
- 💬 Telegram: @yourusername

---

## ✅ Чеклист готовности

После завершения быстрого старта у вас должно быть:

- [x] Получены API ключи Binance Testnet
- [x] Настроен .env файл со всеми ключами
- [x] Запущены Docker контейнеры (PostgreSQL, Redis)
- [x] Создан Umbrella проект с 4 приложениями
- [x] Создана база данных
- [x] Установлены все зависимости
- [x] Запущен Phoenix сервер на http://localhost:4000
- [x] Проверено подключение к Binance API

**Поздравляем! 🎉 Вы готовы к разработке!**

Следующий шаг: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) → Этап 3: База данных и схемы

---

⏱ **Время на настройку**: 15-30 минут

🚀 **Готовы начать разработку!**
