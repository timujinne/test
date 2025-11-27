# Инструкции по запуску Binance Trading System

## Текущий статус

✅ Проект клонирован: `/home/tim/projects/binance_system`
✅ Docker образ собирается: `elixir-dev:v1.0.0`
✅ Конфигурационные файлы подготовлены

## Что нужно сделать

### 1. Дождаться завершения сборки образа

Сборка Docker образа идет в фоновом режиме и займет 10-15 минут.

Проверить статус:
```bash
docker images | grep elixir-dev
```

### 2. Настроить .env файл

```bash
cd /home/tim/projects/binance_system

# Скопируйте шаблон
cp .env.example .env

# Отредактируйте .env
nano .env
```

### Важные настройки в .env:

```env
# Основные настройки
PROJECT_NAME=binance_system
MIX_ENV=dev

# PostgreSQL
POSTGRES_ROOT_PASSWORD=<ваш_сильный_пароль>
POSTGRES_PORT=5433
APP_DB_NAME=binance_system_prod
APP_DB_USER=binance_user
APP_DB_PASSWORD=<сильный_пароль_для_приложения>

# Phoenix
PHOENIX_PORT=4000
PHX_HOST=localhost

# Cloak ключ для шифрования
CLOAK_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)

# SECRET_KEY_BASE (сгенерируйте)
SECRET_KEY_BASE=$(openssl rand -base64 48)

# Binance API (используйте testnet!)
BINANCE_API_KEY=ваш_testnet_api_key
BINANCE_SECRET_KEY=ваш_testnet_secret_key
BINANCE_BASE_URL=https://testnet.binance.vision
```

### 3. Получить Binance Testnet ключи

1. Откройте https://testnet.binance.vision/
2. Войдите через GitHub
3. Создайте API ключ
4. Скопируйте API Key и Secret Key в .env

### 4. Запустить окружение

После завершения сборки образа:

```bash
cd /home/tim/projects/binance_system

# Запустите контейнеры
docker compose -f docker-compose.custom.yml up -d

# Проверьте логи
docker compose -f docker-compose.custom.yml logs -f
```

### 5. Инициализировать проект

```bash
# Подключитесь к контейнеру
docker compose -f docker-compose.custom.yml exec app bash

# Внутри контейнера:
mix deps.get                 # Установка зависимостей
mix ecto.create              # Создание БД
mix ecto.migrate             # Миграции
mix phx.server               # Запуск Phoenix

# Или используйте Makefile команды:
make db-create
make db-migrate
make server
```

### 6. Доступ к приложению

После запуска Phoenix сервера:
- Web интерфейс: http://localhost:4000
- LiveDashboard: http://localhost:4000/dev/dashboard

## Полезные команды

### Docker управление

```bash
# Запуск
docker compose -f docker-compose.custom.yml up -d

# Остановка
docker compose -f docker-compose.custom.yml down

# Логи
docker compose -f docker-compose.custom.yml logs -f app

# Подключение к контейнеру
docker compose -f docker-compose.custom.yml exec app bash

# Подключение к PostgreSQL
docker compose -f docker-compose.custom.yml exec postgres psql -U binance_user -d binance_system_prod
```

### Mix команды (внутри контейнера)

```bash
mix deps.get                 # Зависимости
mix compile                  # Компиляция
mix test                     # Тесты
mix ecto.create              # Создание БД
mix ecto.migrate             # Миграции
mix phx.server               # Запуск Phoenix
iex -S mix phx.server        # Phoenix с IEx
mix format                   # Форматирование
mix credo                    # Проверка качества
```

### Makefile команды (внутри контейнера)

```bash
make help                    # Список всех команд
make server                  # Запуск сервера
make test                    # Тесты
make db-create               # Создание БД
make db-migrate              # Миграции
make check                   # Полная проверка (format + credo + tests)
```

## Структура проекта

```
binance_system/
├── apps/
│   ├── shared_data/         # Общие данные и Ecto Repo
│   ├── data_collector/      # Интеграция с Binance API
│   ├── trading_engine/      # Торговая логика
│   └── dashboard_web/       # Phoenix UI
├── config/                  # Конфигурация
├── docker-compose.custom.yml # Наша конфигурация
├── init-db-secure.sh        # Безопасная инициализация БД
└── .env                     # Переменные окружения (создайте!)
```

## Безопасность

⚠️ **ВАЖНО:**
- Используйте только testnet для разработки!
- Не коммитьте .env файл в git
- Регулярно ротируйте API ключи
- Никогда не давайте права на вывод средств API ключам

## Troubleshooting

### Образ еще не собран

```bash
# Проверьте статус сборки
docker images | grep elixir-dev

# Если образа нет, запустите сборку заново
cd /home/tim
./build-elixir-dev-image.sh 1.0.0
```

### Ошибка подключения к БД

```bash
# Перезапустите PostgreSQL
docker compose -f docker-compose.custom.yml restart postgres

# Проверьте healthcheck
docker inspect binance_system_postgres --format='{{.State.Health.Status}}'
```

### Порт занят

```bash
# Измените PHOENIX_PORT в .env
PHOENIX_PORT=4001

# Перезапустите контейнеры
docker compose -f docker-compose.custom.yml down
docker compose -f docker-compose.custom.yml up -d
```

## Дополнительная документация

- `README.md` - Основная документация проекта
- `CLAUDE.md` - Руководство для работы с Claude Code
- `DEPLOYMENT_GUIDE.md` - Полное руководство по развертыванию (в /home/tim/)
- `QUICKSTART.md` - Быстрый старт
- `DOCKER_GUIDE.md` - Docker руководство

## Следующие шаги

После успешного запуска:

1. Изучите документацию проекта в `README.md`
2. Настройте торговые стратегии
3. Протестируйте на testnet
4. Изучите мониторинг в LiveDashboard
5. Ознакомьтесь с аудит-отчетом в `AUDIT_REPORT.md`

---

**Готово!** Когда образ соберется, следуйте инструкциям выше для запуска проекта.
