# Makefile для упрощения команд разработки

.PHONY: help setup start stop restart logs clean test db-reset

# Цвета для вывода
GREEN  := \033[0;32m
YELLOW := \033[0;33m
NC     := \033[0m

help: ## Показать эту справку
	@echo "$(GREEN)Доступные команды:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Первичная настройка проекта
	@echo "$(GREEN)Установка зависимостей...$(NC)"
	cp .env.example .env
	@echo "$(YELLOW)⚠️  Отредактируйте .env файл с вашими ключами!$(NC)"
	docker-compose up -d postgres redis
	@echo "$(GREEN)Ожидание запуска БД...$(NC)"
	sleep 5
	@echo "$(GREEN)Готово! Теперь создайте umbrella проект:$(NC)"
	@echo "  mix new binance_system --umbrella"

start: ## Запустить основные сервисы (postgres, redis, dev)
	@echo "$(GREEN)Запуск сервисов...$(NC)"
	docker-compose up -d postgres redis dev

start-all: ## Запустить все сервисы включая мониторинг и инструменты
	@echo "$(GREEN)Запуск всех сервисов...$(NC)"
	docker-compose --profile monitoring --profile tools up -d

start-monitoring: ## Запустить с мониторингом (Grafana + Prometheus)
	@echo "$(GREEN)Запуск с мониторингом...$(NC)"
	docker-compose --profile monitoring up -d

start-tools: ## Запустить с инструментами (pgAdmin + Redis Commander)
	@echo "$(GREEN)Запуск с инструментами...$(NC)"
	docker-compose --profile tools up -d

stop: ## Остановить все сервисы
	@echo "$(YELLOW)Остановка сервисов...$(NC)"
	docker-compose down

restart: stop start ## Перезапустить сервисы

logs: ## Показать логи всех сервисов
	docker-compose logs -f

logs-app: ## Показать логи приложения
	docker-compose logs -f app

logs-postgres: ## Показать логи PostgreSQL
	docker-compose logs -f postgres

logs-redis: ## Показать логи Redis
	docker-compose logs -f redis

ps: ## Показать статус контейнеров
	docker-compose ps

clean: ## Очистить все данные (ВНИМАНИЕ: удаляет БД!)
	@echo "$(YELLOW)⚠️  Это удалит все данные! Продолжить? [y/N]$(NC)"
	@read -r REPLY; \
	if [ "$$REPLY" = "y" ]; then \
		echo "$(YELLOW)Удаление данных...$(NC)"; \
		docker-compose down -v; \
		rm -rf _build deps; \
		echo "$(GREEN)Готово!$(NC)"; \
	else \
		echo "Отменено."; \
	fi

# === Elixir команды ===

deps: ## Установить зависимости Elixir
	mix deps.get

compile: ## Скомпилировать проект
	mix compile

test: ## Запустить тесты
	mix test

test-watch: ## Запустить тесты в watch режиме
	mix test.watch

format: ## Форматировать код
	mix format

credo: ## Проверить качество кода
	mix credo --strict

dialyzer: ## Запустить статический анализ типов
	mix dialyzer

# === База данных ===

db-create: ## Создать базу данных
	mix ecto.create

db-migrate: ## Запустить миграции
	mix ecto.migrate

db-rollback: ## Откатить последнюю миграцию
	mix ecto.rollback

db-reset: ## Пересоздать БД (ВНИМАНИЕ: удаляет данные!)
	mix ecto.reset

db-seed: ## Заполнить БД тестовыми данными
	mix run priv/repo/seeds.exs

db-shell: ## Открыть psql консоль
	docker exec -it binance_postgres psql -U postgres -d binance_trading_dev

db-shell-dev: ## Открыть psql из контейнера dev
	docker exec -it binance_dev psql -h postgres -U postgres -d binance_trading_dev

db-backup: ## Создать бэкап базы данных
	@echo "$(GREEN)Создание бэкапа...$(NC)"
	docker exec -t binance_postgres pg_dump -U postgres binance_trading_dev > backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)Бэкап создан!$(NC)"

db-restore: ## Восстановить базу из бэкапа (использование: make db-restore file=backup.sql)
	@echo "$(YELLOW)Восстановление из $(file)...$(NC)"
	docker exec -i binance_postgres psql -U postgres -d binance_trading_dev < $(file)
	@echo "$(GREEN)Готово!$(NC)"

# === Phoenix команды ===

server: ## Запустить Phoenix сервер
	mix phx.server

server-iex: ## Запустить Phoenix с IEx консолью
	iex -S mix phx.server

routes: ## Показать все маршруты
	mix phx.routes

# === Docker команды ===

docker-build: ## Собрать Docker образ для разработки
	docker-compose build dev

docker-rebuild: ## Пересобрать образ без кеша
	docker-compose build --no-cache dev

docker-shell: ## Открыть bash shell в контейнере разработки
	docker exec -it binance_dev bash

docker-tmux: ## Открыть tmux сессию в контейнере
	docker exec -it binance_dev tmux new -s dev

docker-iex: ## Открыть IEx в контейнере
	docker exec -it binance_dev iex -S mix

docker-exec: ## Выполнить команду в контейнере (использование: make docker-exec cmd="mix test")
	docker exec -it binance_dev $(cmd)

docker-logs-dev: ## Показать логи контейнера разработки
	docker-compose logs -f dev

docker-stats: ## Показать использование ресурсов контейнерами
	docker stats binance_dev binance_postgres binance_redis

# === Генерация ===

gen-secret: ## Сгенерировать Phoenix secret key
	mix phx.gen.secret

gen-migration: ## Создать новую миграцию (использование: make gen-migration name=create_users)
	mix ecto.gen.migration $(name)

# === Мониторинг ===

open-grafana: ## Открыть Grafana в браузере
	@echo "$(GREEN)Открытие Grafana...$(NC)"
	@echo "URL: http://localhost:3000"
	@echo "Login: admin / Password: admin"

open-pgadmin: ## Открыть pgAdmin в браузере
	@echo "$(GREEN)Открытие pgAdmin...$(NC)"
	@echo "URL: http://localhost:5050"
	@echo "Login: admin@admin.com / Password: admin"

open-redis-commander: ## Открыть Redis Commander
	@echo "$(GREEN)Открытие Redis Commander...$(NC)"
	@echo "URL: http://localhost:8081"

# === Документация ===

docs: ## Сгенерировать документацию
	mix docs

docs-open: docs ## Открыть документацию в браузере
	open doc/index.html

# === Release ===

release-build: ## Собрать production release
	MIX_ENV=prod mix release

release-run: ## Запустить production release
	_build/prod/rel/binance_system/bin/binance_system start

# === Качество кода ===

check: format credo test ## Полная проверка кода (format + credo + tests)

ci: ## Запустить CI проверки
	mix format --check-formatted
	mix credo --strict
	mix test --cover
	mix dialyzer

# === Информация ===

info: ## Показать информацию о системе
	@echo "$(GREEN)=== Информация о системе ===$(NC)"
	@echo "Elixir version: $$(elixir --version | head -1)"
	@echo "Mix version: $$(mix --version)"
	@echo "PostgreSQL: $$(docker-compose exec postgres psql --version)"
	@echo "Redis: $$(docker-compose exec redis redis-cli --version)"
	@echo ""
	@echo "$(GREEN)=== Статус контейнеров ===$(NC)"
	@docker-compose ps
