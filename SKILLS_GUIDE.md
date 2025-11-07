# 🎯 Руководство по Skills для Claude Code

## Что такое Skills?

**Skills** в Claude Code — это переиспользуемые модули, которые помогают автоматизировать повторяющиеся задачи разработки. Они могут быть встроенными (от Anthropic) или пользовательскими (созданные вами).

---

## 📦 Встроенные Skills

### session-start-hook

Доступен в вашем проекте. Используется для настройки startup hooks для Claude Code.

**Когда использовать:**
- Настройка репозитория для работы с Claude Code
- Автоматический запуск тестов/линтеров при старте сессии

**Как использовать:**
```bash
# В Claude Code CLI
/skill session-start-hook
```

---

## 🛠 Создание собственных Skills

### Структура проекта для Skills

```
your_project/
├── .claude/
│   └── skills/
│       ├── elixir_module.md
│       ├── phoenix_live.md
│       ├── binance_test.md
│       └── migration.md
```

---

## 💡 Примеры Skills для Binance System

### 1. Генерация Elixir GenServer модуля

**Файл:** `.claude/skills/elixir_genserver.md`

```markdown
---
name: elixir-genserver
description: Generate Elixir GenServer module with supervision and tests
---

Generate a new Elixir GenServer module with the following structure:

## Module Name
Ask user for the module name (e.g., `TradingEngine.OrderManager`)

## Generate Files

### 1. GenServer Module
Location: `apps/{app}/lib/{app}/{path}/{module}.ex`

```elixir
defmodule {ModuleName} do
  use GenServer
  require Logger

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks
  @impl true
  def init(opts) do
    Logger.info("Starting #{__MODULE__}")
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
```

### 2. Test File
Location: `apps/{app}/test/{app}/{path}/{module}_test.exs`

```elixir
defmodule {ModuleName}Test do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = {ModuleName}.start_link([])
    %{pid: pid}
  end

  test "starts successfully", %{pid: pid} do
    assert Process.alive?(pid)
  end

  test "returns state", %{pid: _pid} do
    state = {ModuleName}.get_state()
    assert is_map(state)
  end
end
```

### 3. Add to Supervision Tree
Provide instructions to add to `application.ex`:

```elixir
children = [
  {ModuleName}, []}
]
```
```

---

### 2. Phoenix LiveView Component

**Файл:** `.claude/skills/phoenix_liveview.md`

```markdown
---
name: phoenix-liveview
description: Generate Phoenix LiveView component with tests
---

Generate a new Phoenix LiveView component.

## Component Name
Ask user for the component name (e.g., `TradingLive`, `PortfolioLive`)

## Generate Files

### 1. LiveView Module
Location: `apps/dashboard_web/lib/dashboard_web/live/{component}_live.ex`

```elixir
defmodule DashboardWeb.{Component}Live do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, data: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <h1>{@page_title}</h1>
      <!-- Add your content here -->
    </div>
    """
  end
end
```

### 2. Test File
Location: `apps/dashboard_web/test/dashboard_web/live/{component}_live_test.exs`

```elixir
defmodule DashboardWeb.{Component}LiveTest do
  use DashboardWeb.ConnCase
  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, "/{route}")
    assert disconnected_html =~ "Page Title"
    assert render(page_live) =~ "Page Title"
  end
end
```

### 3. Add Route
Instructions to add to `router.ex`:

```elixir
live "/{route}", {Component}Live, :index
```
```

---

### 3. Database Migration Generator

**Файл:** `.claude/skills/db_migration.md`

```markdown
---
name: db-migration
description: Generate Ecto migration with common patterns
---

Generate a new Ecto migration file.

## Migration Type
Ask user to choose:
1. Create table
2. Add column
3. Add index
4. Create hypertable (TimescaleDB)

## For "Create Table"

```bash
mix ecto.gen.migration create_{table_name}
```

Then populate with:

```elixir
defmodule SharedData.Repo.Migrations.Create{TableName} do
  use Ecto.Migration

  def change do
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Add columns here

      timestamps()
    end

    # Add indexes
    create index(:{table_name}, [:field])
  end
end
```

## For "Create Hypertable" (TimescaleDB)

```elixir
defmodule SharedData.Repo.Migrations.Create{TableName}Hypertable do
  use Ecto.Migration
  import Timescale.Migration

  def up do
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      # Add columns

      timestamps()
    end

    create_hypertable(:{table_name}, :timestamp, chunk_time_interval: "1 day")
    create index(:{table_name}, [:timestamp])
  end

  def down do
    drop table(:{table_name})
  end
end
```
```

---

### 4. Binance API Test Helper

**Файл:** `.claude/skills/binance_test.md`

```markdown
---
name: binance-test
description: Generate test helpers for Binance API mocking
---

Generate Binance API test helpers and mocks.

## Create Test Helper Module

Location: `test/support/binance_mock.ex`

```elixir
defmodule BinanceMock do
  @moduledoc """
  Mock responses for Binance API testing
  """

  def mock_account_info do
    %{
      "makerCommission" => 10,
      "takerCommission" => 10,
      "buyerCommission" => 0,
      "sellerCommission" => 0,
      "canTrade" => true,
      "canWithdraw" => false,
      "canDeposit" => false,
      "updateTime" => 1234567890000,
      "balances" => [
        %{"asset" => "BTC", "free" => "10.00000000", "locked" => "0.00000000"},
        %{"asset" => "USDT", "free" => "10000.00000000", "locked" => "0.00000000"}
      ]
    }
  end

  def mock_order_response do
    %{
      "symbol" => "BTCUSDT",
      "orderId" => 123456,
      "clientOrderId" => "test_order_1",
      "transactTime" => 1234567890000,
      "price" => "50000.00",
      "origQty" => "0.001",
      "executedQty" => "0.001",
      "status" => "FILLED",
      "type" => "LIMIT",
      "side" => "BUY"
    }
  end

  def mock_ticker_price(symbol \\ "BTCUSDT") do
    %{
      "symbol" => symbol,
      "price" => "50000.00"
    }
  end
end
```

## Usage in Tests

```elixir
defmodule TradingEngineTest do
  use ExUnit.Case
  import BinanceMock

  setup do
    # Mock HTTP client
    Tesla.Mock.mock(fn
      %{method: :get, url: "/api/v3/account"} ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(mock_account_info())}}

      %{method: :post, url: "/api/v3/order"} ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(mock_order_response())}}
    end)

    :ok
  end

  test "places order successfully" do
    # Your test code
  end
end
```
```

---

## 🎯 Использование Skills

### Способ 1: Через Claude Code CLI

```bash
# Список доступных skills
/skills list

# Использовать skill
/skill elixir-genserver

# Использовать встроенный skill
/skill session-start-hook
```

### Способ 2: Через команды

После создания `.claude/skills/` директории, skills становятся доступны автоматически.

---

## 📝 Синтаксис Skills

### Frontmatter (обязательно)

```markdown
---
name: skill-name              # Уникальное имя (kebab-case)
description: Short description # Краткое описание
tags: elixir, phoenix          # Теги (опционально)
---
```

### Содержимое

Skills могут содержать:
- Инструкции для Claude Code
- Шаблоны кода
- Bash команды
- Описание файловой структуры
- Примеры использования

---

## 🔧 Лучшие практики

### 1. Делайте Skills специфичными
❌ **Плохо:** "Generate code"
✅ **Хорошо:** "Generate Elixir GenServer with supervision and tests"

### 2. Включайте примеры
Всегда добавляйте примеры использования сгенерированного кода.

### 3. Учитывайте контекст проекта
Skills должны следовать структуре и соглашениям вашего проекта.

### 4. Добавляйте тесты
Генерируйте тесты вместе с основным кодом.

### 5. Документируйте зависимости
Указывайте необходимые библиотеки и настройки.

---

## 📚 Дополнительные Skills для проекта

### Рекомендуемые Skills для Binance System:

1. **strategy-generator** - Генерация новых торговых стратегий
2. **channel-setup** - Создание Phoenix Channels
3. **schema-generator** - Генерация Ecto схем с шифрованием
4. **supervisor-tree** - Настройка supervision деревьев
5. **api-client** - Генерация HTTP клиентов с rate limiting

---

## 🎓 Обучающие ресурсы

- [Claude Code Skills Documentation](https://docs.claude.com/claude-code)
- [Elixir Mix Tasks](https://hexdocs.pm/mix/Mix.Task.html)
- [Phoenix Generators](https://hexdocs.pm/phoenix/Mix.Tasks.Phx.Gen.html)

---

## 💡 Идеи для Skills

### Для нашего проекта можно создать:

1. **binance-strategy**
   - Шаблон торговой стратегии
   - С backtesting setup
   - Mock данные для тестов

2. **risk-manager**
   - Risk management модуль
   - Stop-loss/take-profit логика
   - Position sizing калькулятор

3. **dashboard-widget**
   - LiveView компонент для dashboard
   - Real-time обновления
   - Chart интеграция

4. **api-endpoint**
   - REST API endpoint
   - С валидацией
   - OpenAPI документация

---

## 📞 Помощь

Если нужна помощь с созданием Skills:
1. Изучите примеры выше
2. Следуйте структуре Markdown
3. Тестируйте Skills перед использованием
4. Документируйте зависимости

**Готовы создавать свои Skills? Начните с простого и постепенно расширяйте функционал!** 🚀
