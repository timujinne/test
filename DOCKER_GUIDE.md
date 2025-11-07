# 🐳 Docker Development Guide

Руководство по использованию Docker окружения для разработки Binance Trading System.

## 📋 Содержание

- [Быстрый старт](#быстрый-старт)
- [Управление контейнерами](#управление-контейнерами)
- [Работа с базой данных](#работа-с-базой-данных)
- [Полезные команды](#полезные-команды)
- [Troubleshooting](#troubleshooting)

---

## 🚀 Быстрый старт

### 1. Подготовка окружения

```bash
# Скопировать пример файла с переменными окружения
cp .env.example .env

# Отредактировать .env файл с вашими настройками
nano .env
```

### 2. Сборка и запуск контейнеров

```bash
# Собрать образ для разработки
docker compose build dev

# Запустить основные сервисы (postgres, redis, dev)
docker compose up -d

# ИЛИ с мониторингом (grafana, prometheus)
docker compose --profile monitoring up -d

# ИЛИ с дополнительными инструментами (pgadmin, redis-commander)
docker compose --profile tools up -d

# ИЛИ всё сразу
docker compose --profile monitoring --profile tools up -d
```

### 3. Войти в контейнер разработки

```bash
# Вариант 1: обычный bash
docker exec -it binance_dev bash

# Вариант 2: через tmux (рекомендуется)
docker exec -it binance_dev tmux

# Вариант 3: запустить конкретную команду
docker exec -it binance_dev mix deps.get
```

### 4. Настроить базу данных

```bash
# Войти в контейнер
docker exec -it binance_dev bash

# Создать базу данных
mix ecto.create

# Запустить миграции
mix ecto.migrate

# (Опционально) Заполнить тестовыми данными
mix run priv/repo/seeds.exs
```

### 5. Запустить Phoenix сервер

```bash
# Внутри контейнера
mix phx.server

# ИЛИ с IEx консолью
iex -S mix phx.server
```

Откройте браузер: http://localhost:4000

---

## 🎮 Управление контейнерами

### Основные команды

```bash
# Просмотр запущенных контейнеров
docker compose ps

# Остановить все сервисы
docker compose down

# Остановить и удалить volumes (⚠️ удалит данные БД!)
docker compose down -v

# Перезапустить конкретный сервис
docker compose restart dev

# Посмотреть логи
docker compose logs -f dev
docker compose logs -f postgres
docker compose logs -f redis

# Посмотреть логи всех сервисов
docker compose logs -f
```

### Пересборка образа

```bash
# Пересобрать образ после изменения Dockerfile.dev
docker compose build --no-cache dev

# Пересобрать и перезапустить
docker compose up -d --build dev
```

---

## 💾 Работа с базой данных

### PostgreSQL через psql

```bash
# Подключиться к PostgreSQL из контейнера dev
docker exec -it binance_dev psql -h postgres -U postgres -d binance_trading_dev

# ИЛИ напрямую к контейнеру postgres
docker exec -it binance_postgres psql -U postgres -d binance_trading_dev
```

### Полезные SQL команды

```sql
-- Список таблиц
\dt

-- Описание таблицы
\d users

-- Список баз данных
\l

-- Выход
\q
```

### Бэкап и восстановление

```bash
# Создать бэкап
docker exec -t binance_postgres pg_dump -U postgres binance_trading_dev > backup.sql

# Восстановить из бэкапа
docker exec -i binance_postgres psql -U postgres -d binance_trading_dev < backup.sql
```

### Проверка TimescaleDB

```bash
# Войти в PostgreSQL
docker exec -it binance_postgres psql -U postgres -d binance_trading_dev

# Проверить расширение
SELECT default_version, installed_version FROM pg_available_extensions WHERE name = 'timescaledb';

# Создать hypertable (пример)
-- SELECT create_hypertable('trades', 'inserted_at');
```

---

## 🛠 Полезные команды

### Работа с Elixir/Phoenix

```bash
# Войти в контейнер
docker exec -it binance_dev bash

# Установить зависимости
mix deps.get
mix deps.compile

# Запустить тесты
mix test
mix test --cover

# Форматирование кода
mix format

# Статический анализ
mix credo --strict

# Запустить IEx
iex -S mix

# Очистка build артефактов
mix clean
rm -rf _build deps
```

### Работа с Node.js/NPM (для Phoenix assets)

```bash
# Войти в директорию assets
cd assets

# Установить зависимости
npm install

# Собрать assets
npm run build

# Watch режим
npm run watch
```

### Работа с Git (lazygit)

```bash
# Запустить lazygit TUI
docker exec -it binance_dev lazygit
```

### Работа с Tmux

```bash
# Запустить новую tmux сессию
docker exec -it binance_dev tmux new -s dev

# Подключиться к существующей сессии
docker exec -it binance_dev tmux attach -t dev

# Горячие клавиши (префикс Ctrl+a):
# Ctrl+a |  - разделить окно вертикально
# Ctrl+a -  - разделить окно горизонтально
# Ctrl+a d  - отсоединиться от сессии
# Ctrl+a c  - создать новое окно
# Ctrl+a n  - следующее окно
# Ctrl+a p  - предыдущее окно
```

---

## 🔍 Мониторинг и отладка

### Доступ к веб-интерфейсам

После запуска с профилями:

```bash
docker compose --profile monitoring --profile tools up -d
```

Доступны следующие интерфейсы:

- **Phoenix App**: http://localhost:4000
- **Phoenix LiveDashboard**: http://localhost:4000/dashboard
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **pgAdmin**: http://localhost:5050 (admin@admin.com/admin)
- **Redis Commander**: http://localhost:8081 (admin/admin)

### Просмотр метрик

```bash
# Использование ресурсов контейнерами
docker stats

# Детальная информация о контейнере
docker inspect binance_dev

# Healthcheck статус
docker inspect --format='{{json .State.Health}}' binance_dev | jq
```

### Логи

```bash
# Все логи
docker compose logs -f

# Конкретный сервис
docker compose logs -f dev
docker compose logs -f postgres

# Последние N строк
docker compose logs --tail=100 dev
```

---

## 🐛 Troubleshooting

### Проблема: Контейнер не запускается

```bash
# Проверить логи
docker compose logs dev

# Проверить healthcheck
docker inspect --format='{{json .State.Health}}' binance_dev | jq

# Пересобрать без кеша
docker compose build --no-cache dev
```

### Проблема: База данных недоступна

```bash
# Проверить статус PostgreSQL
docker compose ps postgres

# Проверить healthcheck
docker exec binance_postgres pg_isready -U postgres

# Перезапустить PostgreSQL
docker compose restart postgres

# Посмотреть логи
docker compose logs postgres
```

### Проблема: Порты заняты

```bash
# Проверить, что слушает порт 4000
sudo lsof -i :4000

# ИЛИ
sudo netstat -tulpn | grep 4000

# Изменить порты в docker-compose.yml или .env файле
```

### Проблема: Недостаточно места на диске

```bash
# Очистка неиспользуемых Docker данных
docker system prune -a --volumes

# ⚠️ ОСТОРОЖНО: удалит ВСЕ volumes (включая БД!)
docker compose down -v
```

### Проблема: Mix deps не устанавливаются

```bash
# Очистить volumes с зависимостями
docker volume rm binance_elixir_deps binance_elixir_build

# Пересобрать
docker compose build --no-cache dev
docker compose up -d dev

# Установить зависимости заново
docker exec -it binance_dev mix deps.get
```

### Проблема: Permission denied при монтировании volumes

На Linux может потребоваться настроить права:

```bash
# Узнать UID/GID в контейнере
docker exec -it binance_dev id

# Дать права на директорию проекта
sudo chown -R $(id -u):$(id -g) .

# ИЛИ запустить контейнер от своего пользователя (добавить в docker-compose.yml)
# user: "${UID}:${GID}"
```

---

## 📚 Дополнительные ресурсы

### Документация проекта

- [README.md](README.md) - Основная документация
- [QUICKSTART.md](QUICKSTART.md) - Быстрый старт
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - План реализации

### Docker

- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

### Elixir/Phoenix

- [Elixir Getting Started](https://elixir-lang.org/getting-started/introduction.html)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix on Docker](https://hexdocs.pm/phoenix/releases.html#containers)

---

## 💡 Советы по разработке

### 1. Используйте tmux для мультиплексирования

```bash
docker exec -it binance_dev tmux

# Создайте несколько панелей:
# Ctrl+a | - создать вертикальную панель
# - Панель 1: mix phx.server
# - Панель 2: iex -S mix
# - Панель 3: mix test.watch
```

### 2. Используйте watch режимы

```bash
# Phoenix live reload уже включен по умолчанию

# Для тестов
mix test.watch

# Для assets
cd assets && npm run watch
```

### 3. Используйте IEx для отладки

```elixir
# В коде добавьте
require IEx; IEx.pry()

# Запустите с IEx
iex -S mix phx.server
```

### 4. Сохраняйте историю команд

История bash сохраняется в volume `shell_history`, поэтому доступна между перезапусками.

---

## 🎯 Рабочий процесс (workflow)

### Типичный день разработки

```bash
# 1. Запуск окружения
docker compose up -d

# 2. Войти в контейнер через tmux
docker exec -it binance_dev tmux new -s dev

# 3. В разных панелях tmux:
# Панель 1: Phoenix server
mix phx.server

# Панель 2: Tests в watch режиме
mix test.watch

# Панель 3: IEx для экспериментов
iex -S mix

# 4. По окончании работы
# Ctrl+a d - отсоединиться от tmux
# exit - выйти из контейнера

# 5. Остановка (опционально)
docker compose stop
```

---

**Если у вас возникли вопросы или проблемы, проверьте раздел [Troubleshooting](#troubleshooting) или обратитесь к основной документации.**

Happy coding! 🚀
