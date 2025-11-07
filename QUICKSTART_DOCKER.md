# 🚀 Быстрый старт с Docker

Минимальная инструкция для запуска проекта в Docker.

## Предварительные требования

- Docker 20.10+
- Docker Compose 2.0+

## Шаг 1: Настройка переменных окружения

```bash
# Скопировать пример
cp .env.example .env

# Отредактировать .env (минимально необходимое)
nano .env
```

**Обязательно установите:**
- `BINANCE_API_KEY` - ваш API ключ (testnet или production)
- `BINANCE_SECRET_KEY` - ваш Secret ключ
- `SECRET_KEY_BASE` - сгенерируйте через `mix phx.gen.secret`
- `CLOAK_KEY` - для шифрования (см. ниже)

**Генерация CLOAK_KEY:**
```bash
# В Elixir консоли
iex -S mix
32 |> :crypto.strong_rand_bytes() |> Base.encode64()

# ИЛИ онлайн
# https://www.random.org/bytes/
```

## Шаг 2: Запуск контейнеров

```bash
# Собрать и запустить
docker compose build dev
docker compose up -d

# Проверить статус
docker compose ps
```

**Результат должен быть:**
```
NAME                 STATUS              PORTS
binance_dev          Up                  0.0.0.0:4000->4000/tcp
binance_postgres     Up (healthy)        0.0.0.0:5432->5432/tcp
binance_redis        Up (healthy)        0.0.0.0:6379->6379/tcp
```

## Шаг 3: Войти в контейнер разработки

```bash
# Вариант 1: Обычный bash
docker exec -it binance_dev bash

# Вариант 2: Через tmux (рекомендуется)
docker exec -it binance_dev tmux

# Вариант 3: Через Makefile
make docker-shell
```

## Шаг 4: Настроить базу данных

```bash
# Внутри контейнера (после docker exec -it binance_dev bash)

# Установить зависимости (если нужно)
mix deps.get

# Создать базу данных
mix ecto.create

# Запустить миграции
mix ecto.migrate

# (Опционально) Заполнить тестовыми данными
mix run priv/repo/seeds.exs
```

**ИЛИ используя Makefile снаружи контейнера:**
```bash
make docker-exec cmd="mix deps.get"
make docker-exec cmd="mix ecto.create"
make docker-exec cmd="mix ecto.migrate"
```

## Шаг 5: Запустить Phoenix сервер

```bash
# Внутри контейнера
mix phx.server

# ИЛИ с IEx
iex -S mix phx.server
```

**Готово!** Откройте http://localhost:4000

---

## 🛠 Полезные команды

### Работа с контейнерами

```bash
# Остановить
docker compose down

# Перезапустить
docker compose restart dev

# Посмотреть логи
docker compose logs -f dev

# Статистика использования ресурсов
docker stats
```

### Работа с базой данных

```bash
# Подключиться к PostgreSQL
docker exec -it binance_postgres psql -U postgres -d binance_trading_dev

# ИЛИ из контейнера dev
docker exec -it binance_dev psql -h postgres -U postgres -d binance_trading_dev

# Бэкап
docker exec -t binance_postgres pg_dump -U postgres binance_trading_dev > backup.sql

# Восстановление
docker exec -i binance_postgres psql -U postgres -d binance_trading_dev < backup.sql
```

### Makefile команды

```bash
# Посмотреть все доступные команды
make help

# Запустить контейнеры
make start

# Запустить с мониторингом
make start-all

# Открыть shell
make docker-shell

# Открыть tmux
make docker-tmux

# Выполнить команду
make docker-exec cmd="mix test"
```

---

## 🎯 Рабочий процесс

### Типичный день разработки

```bash
# 1. Запуск
make start
# ИЛИ
docker compose up -d

# 2. Войти в контейнер через tmux
make docker-tmux

# 3. Создать панели в tmux (Ctrl+a |)
# Панель 1: Phoenix server
mix phx.server

# Панель 2: Tests
mix test.watch

# Панель 3: IEx
iex -S mix

# 4. Работать с кодом в вашем любимом редакторе
# Изменения синхронизируются автоматически через volume

# 5. По окончании
# Ctrl+a d - отсоединиться от tmux
docker compose stop
```

---

## 📊 Дополнительные инструменты

### Запуск с мониторингом

```bash
# Запустить с Grafana и Prometheus
docker compose --profile monitoring up -d

# Открыть интерфейсы
make open-grafana    # http://localhost:3000 (admin/admin)
```

### Запуск с инструментами для БД

```bash
# Запустить с pgAdmin и Redis Commander
docker compose --profile tools up -d

# Открыть интерфейсы
make open-pgadmin           # http://localhost:5050 (admin@admin.com/admin)
make open-redis-commander   # http://localhost:8081 (admin/admin)
```

### Всё сразу

```bash
make start-all
```

---

## ❗ Troubleshooting

### Контейнер не запускается

```bash
# Проверить логи
docker compose logs dev

# Пересобрать без кеша
docker compose build --no-cache dev
```

### База данных недоступна

```bash
# Проверить healthcheck
docker exec binance_postgres pg_isready -U postgres

# Перезапустить
docker compose restart postgres
```

### Порт 4000 занят

```bash
# Проверить, кто использует порт
sudo lsof -i :4000

# Изменить в .env или docker-compose.yml
# ports:
#   - "4001:4000"  # Внешний порт 4001
```

### Очистить всё и начать заново

```bash
# ОСТОРОЖНО: удалит все данные!
docker compose down -v
docker system prune -a
```

---

## 📚 Дополнительная документация

- [DOCKER_GUIDE.md](DOCKER_GUIDE.md) - Полное руководство по Docker
- [README.md](README.md) - Основная документация проекта
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - План реализации

---

## 🎉 Готово к разработке!

Теперь у вас есть полноценное окружение для разработки:

✅ **Elixir 1.18.4** + **OTP 28**
✅ **Phoenix Framework**
✅ **PostgreSQL 16** + **TimescaleDB**
✅ **Redis 7**
✅ **Node.js 22** + **NPM**
✅ **Go 1.23.5**
✅ **Python 3**
✅ **tmux**, **vim**, **lazygit** и другие инструменты

**Happy coding!** 🚀
