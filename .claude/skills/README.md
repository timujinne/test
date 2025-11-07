# Skills для Binance Trading System

Эта директория содержит 13 custom skills для автоматизации разработки торговой системы на Elixir/Phoenix.

## 📦 Доступные Skills (13)

### Binance & Trading
1. **binance-api** - Полная интеграция с Binance REST и WebSocket API
2. **trading-strategies** - Реализация торговых стратегий (Naive, Grid, DCA)
3. **websocket-elixir** - WebSocket клиенты для real-time данных

### Elixir Core
4. **elixir-otp** - OTP паттерны (GenServer, Supervisor, DynamicSupervisor)
5. **elixir-security** - Безопасность (шифрование, аутентификация)
6. **elixir-caching** - Кеширование (ETS, Nebulex, Redis)
7. **elixir-testing** - Тестирование (ExUnit, Mox, StreamData)
8. **elixir-deployment** - Деплой и релизы
9. **genstage-flow** - GenStage и Flow для обработки потоков

### Phoenix Framework
10. **phoenix-framework** - Базовые Phoenix концепции
11. **phoenix-liveview** - Phoenix LiveView компоненты
12. **phoenix-channels** - Phoenix Channels для WebSocket

### Database
13. **ecto-timescale** - Ecto схемы с TimescaleDB для time-series данных

## 🎯 Использование

### В Claude Code CLI:

```bash
# Просмотр доступных skills
/skills list

# Использование конкретного skill
/skill binance-api
/skill trading-strategies
/skill phoenix-liveview
```

### Примеры применения:

**Создание Binance клиента:**
```bash
/skill binance-api
# Claude создаст REST и WebSocket клиенты с rate limiting
```

**Генерация торговой стратегии:**
```bash
/skill trading-strategies
# Создаст GenServer с логикой стратегии
```

**Создание LiveView компонента:**
```bash
/skill phoenix-liveview
# Сгенерирует LiveView с тестами
```

## 📊 Статистика

- **Всего skills**: 13
- **Строк кода/документации**: 2,360
- **Категорий**: 4 (Binance, Elixir, Phoenix, Database)

## 📝 Формат Skill

Каждый skill - это Markdown файл с frontmatter:

```markdown
---
name: skill-name
description: Описание skill
---

# Содержимое skill
...
```

## 🔧 Создание новых Skills

См. [SKILLS_GUIDE.md](../../SKILLS_GUIDE.md) в корне проекта для подробной инструкции.

## 📚 Документация Skills

### binance-api (18 КБ)
Полная интеграция с Binance:
- REST API клиент с rate limiting
- WebSocket стримы для market data
- Аутентификация и подписи
- Error handling и reconnection
- Примеры для всех endpoints

### trading-strategies (2.8 КБ)
Торговые стратегии:
- Naive (buy-low, sell-high)
- Grid (сеточная торговля)
- DCA (dollar cost averaging)
- GenServer архитектура
- State management

### phoenix-liveview (5.5 КБ)
LiveView компоненты:
- Реализация mount/render
- Real-time обновления
- PubSub интеграция
- Тесты для LiveView

### elixir-otp (9.2 КБ)
OTP паттерны:
- GenServer implementation
- Supervision trees
- DynamicSupervisor
- Registry для процессов

### ecto-timescale (7 КБ)
TimescaleDB интеграция:
- Hypertables
- Continuous aggregates
- Time-series queries
- Compression policies

## ⚡ Быстрый старт

После клонирования репозитория skills доступны автоматически в Claude Code.

Начните с:
```bash
/skill binance-api     # Для Binance интеграции
/skill elixir-otp      # Для OTP архитектуры
/skill phoenix-liveview # Для UI компонентов
```

---

*Создано: 2025-11-07*
*Skills: 13 | Строк: 2,360*
