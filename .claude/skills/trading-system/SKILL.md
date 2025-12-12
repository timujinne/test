---
name: trading-system
description: Trading system architecture, public APIs, strategy management, conditions, and debugging. Use for implementing trading strategies, managing orders, monitoring positions, and working with the TradingEngine umbrella app.
---

# Trading System

## When to Use This Skill

Use this skill when:
- Implementing or modifying trading strategies (Naive, Grid, DCA, ConditionalChain)
- Working with strategy lifecycle (start/stop, conditions)
- Managing positions and P&L tracking
- Debugging running strategies via IEx
- Implementing start/stop conditions
- Working with PubSub events for real-time updates
- Building trading-related LiveView UI components

## Architecture Overview

### Process Supervision Tree

```
TradingEngine.Application
├── Registry (TradingEngine.TraderRegistry)
│   └── Unique keys for Trader processes by setting_id
├── DynamicSupervisor (TradingEngine.AccountSupervisor)
│   └── Trader processes (one per active setting)
├── StrategyManager (GenServer)
│   └── Lifecycle management, restore on startup
├── SharedPositionTracker (GenServer)
│   └── Position aggregation by (account_id, symbol)
├── AccountCoordinator (GenServer)
│   └── Account-level risk limits and coordination
├── PendingStrategiesManager (GenServer)
│   └── Strategies waiting for start conditions
└── StopConditionsMonitor (GenServer)
    └── Monitors stop conditions for running strategies
```

### Data Flow

```
                    ┌─────────────────────────────────────────┐
                    │           DataCollector                  │
                    │  BinanceWebSocket → PubSub broadcasts    │
                    └────────────────┬────────────────────────┘
                                     │
          ┌──────────────────────────┼──────────────────────────┐
          │                          │                          │
          ▼                          ▼                          ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ PendingStrategies│      │     Trader      │      │ StopConditions  │
│    Manager       │      │   (Strategy)    │      │    Monitor      │
│                 │      │                 │      │                 │
│ Checks start    │      │ on_tick()       │      │ Checks stop     │
│ conditions      │      │ on_execution()  │      │ conditions      │
└────────┬────────┘      └────────┬────────┘      └────────┬────────┘
         │                        │                        │
         │ {:conditions_met}      │ {:place_order}         │ {:strategy_auto_stopped}
         ▼                        ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        StrategyManager                               │
│  - Starts/stops Trader processes                                     │
│  - Routes to PendingStrategiesManager if has start_conditions        │
│  - Registers with StopConditionsMonitor if has stop_conditions       │
└─────────────────────────────────────────────────────────────────────┘
```

### Module Responsibilities

| Module | Responsibility | Registration |
|--------|----------------|--------------|
| `StrategyManager` | Lifecycle management, startup restore | Named GenServer |
| `AccountSupervisor` | DynamicSupervisor for Trader processes | Named Supervisor |
| `Trader` | Strategy execution, market data handling | `{:via, Registry, {TraderRegistry, setting_id}}` |
| `SharedPositionTracker` | Position aggregation, P&L calculation | Named GenServer |
| `AccountCoordinator` | Account-level coordination, risk limits | Named GenServer |
| `PendingStrategiesManager` | Start condition monitoring | Named GenServer |
| `StopConditionsMonitor` | Stop condition monitoring | Named GenServer |
| `StrategyLoader` | Strategy name → module mapping | Module functions |

## Public API Reference

### TradingEngine.StrategyManager

Manages strategy lifecycle - start, stop, and monitoring.

```elixir
# Get list of running strategy setting IDs
TradingEngine.StrategyManager.get_running_strategies()
# => ["setting-uuid-1", "setting-uuid-2"]

# Check if specific strategy is running
TradingEngine.StrategyManager.is_running?("setting-uuid")
# => true | false

# Manually start a strategy (for testing)
TradingEngine.StrategyManager.start_strategy("setting-uuid")
# => {:ok, #PID<0.456.0>} | {:error, :not_found} | {:error, reason}

# Manually stop a strategy
TradingEngine.StrategyManager.stop_strategy("setting-uuid")
# => :ok | {:error, reason}
```

### TradingEngine.AccountCoordinator

Account-level coordination and risk management.

```elixir
# Get account summary with positions and strategies
TradingEngine.AccountCoordinator.get_account_summary(account_id)
# => %{positions: [...], strategies: [...], daily_pnl: Decimal, ...}

# Check if order can be placed (risk limits)
TradingEngine.AccountCoordinator.can_place_order?(account_id, order_params)
# => {:ok, :allowed} | {:error, :max_position_exceeded} | {:error, :max_daily_loss}

# List active accounts with running strategies
TradingEngine.AccountCoordinator.list_active_accounts()
# => [account_id_1, account_id_2]

# Get strategies for specific account
TradingEngine.AccountCoordinator.get_account_strategies(account_id)
# => [%{setting_id: ..., strategy_name: ..., config: ...}]

# Get aggregated position for account/symbol
TradingEngine.AccountCoordinator.get_aggregated_position(account_id, "BTCUSDT")
# => %{quantity: Decimal, avg_price: Decimal, unrealized_pnl: Decimal}
```

### TradingEngine.SharedPositionTracker

Tracks positions across all accounts and strategies.

```elixir
# Get position for account/symbol
TradingEngine.SharedPositionTracker.get_position(account_id, "BTCUSDT")
# => %{quantity: Decimal, avg_entry_price: Decimal, realized_pnl: Decimal, unrealized_pnl: Decimal}

# Get all positions for account
TradingEngine.SharedPositionTracker.get_account_positions(account_id)
# => [%{symbol: "BTCUSDT", ...}, %{symbol: "ETHUSDT", ...}]

# Get all positions across all accounts
TradingEngine.SharedPositionTracker.get_all_positions()
# => [{account_id, symbol, position_map}, ...]

# Record a fill (called by Trader on execution)
TradingEngine.SharedPositionTracker.record_fill(account_id, %{
  symbol: "BTCUSDT",
  side: "BUY",
  quantity: Decimal.new("0.001"),
  price: Decimal.new("45000")
})
# => :ok

# Update market price for unrealized P&L calculation
TradingEngine.SharedPositionTracker.update_market_price("BTCUSDT", Decimal.new("46000"))
# => :ok

# Close position (resets to zero)
TradingEngine.SharedPositionTracker.close_position(account_id, "BTCUSDT")
# => :ok
```

### TradingEngine.PendingStrategiesManager

Manages strategies waiting for start conditions.

```elixir
# Add strategy to pending queue
TradingEngine.PendingStrategiesManager.add_pending(setting)
# => :ok

# Remove from pending
TradingEngine.PendingStrategiesManager.remove_pending(setting_id)
# => :ok

# List pending strategy IDs
TradingEngine.PendingStrategiesManager.list_pending()
# => ["setting-uuid-1", "setting-uuid-2"]

# Check if strategy is pending
TradingEngine.PendingStrategiesManager.is_pending?(setting_id)
# => true | false
```

### TradingEngine.StopConditionsMonitor

Monitors stop conditions for running strategies.

```elixir
# Start monitoring strategy for stop conditions
TradingEngine.StopConditionsMonitor.monitor_strategy(setting, %{
  entry_price: Decimal.new("45000"),
  position_size: Decimal.new("0.001"),
  started_at: DateTime.utc_now()
})
# => :ok

# Stop monitoring
TradingEngine.StopConditionsMonitor.unmonitor_strategy(setting_id)
# => :ok

# Update P&L data for condition evaluation
TradingEngine.StopConditionsMonitor.update_pnl(setting_id, %{
  current_pnl: Decimal.new("150"),
  pnl_percent: Decimal.new("3.5")
})
# => :ok

# List monitored strategy IDs
TradingEngine.StopConditionsMonitor.list_monitored()
# => ["setting-uuid-1"]
```

### TradingEngine.StrategyLoader

Maps strategy names to implementation modules.

```elixir
# Get module by name (raises on unknown)
TradingEngine.StrategyLoader.get_strategy_module("naive")
# => TradingEngine.Strategies.Naive

# Safe version (returns tuple)
TradingEngine.StrategyLoader.get_strategy_module_safe("naive")
# => {:ok, TradingEngine.Strategies.Naive} | {:error, :unknown_strategy}

# List available strategies
TradingEngine.StrategyLoader.available_strategies()
# => ["naive", "grid", "dca", "conditional_chain"]

# Check if strategy exists
TradingEngine.StrategyLoader.valid_strategy?("naive")
# => true

# Register custom strategy (runtime, not persisted)
TradingEngine.StrategyLoader.register_strategy("my_strategy", MyApp.Strategies.Custom)
# => :ok
```

### TradingEngine.Conditions.ConditionEvaluator

Evaluates start/stop conditions with AND/OR logic.

```elixir
# Initialize evaluator state
config = %{
  "logic" => "and",
  "conditions" => [
    %{"type" => "price", "operator" => "below", "value" => 50000}
  ]
}
{:ok, state} = TradingEngine.Conditions.ConditionEvaluator.init(config)

# Evaluate conditions
market_data = %{"c" => "49500", "v" => "1000000"}
{met?, new_state} = TradingEngine.Conditions.ConditionEvaluator.evaluate(config, market_data, state)
# => {true, updated_state}

# Check if config has conditions
TradingEngine.Conditions.ConditionEvaluator.has_conditions?(config)
# => true

# Get description
TradingEngine.Conditions.ConditionEvaluator.describe(state)
# => "Price below 50000"

# Register custom condition type
TradingEngine.Conditions.ConditionEvaluator.register_condition("rsi", MyApp.Conditions.RSI)
# => :ok
```

## Strategy Implementation

### Strategy Behaviour

All strategies must implement `TradingEngine.Strategy` behaviour:

```elixir
@behaviour TradingEngine.Strategy

# Required callbacks
@callback init(config :: map()) :: {:ok, state :: any()}
@callback on_tick(market_data :: map(), state :: any()) :: {action(), state}
@callback on_execution(execution :: map(), state :: any()) :: {action(), state}

# Optional callbacks
@callback requirements(config :: map()) :: requirements()
@callback on_timer(timer_ref :: reference(), state :: any()) :: {action(), state}
@callback on_order_placed(order :: map(), state :: any()) :: state
@callback required_symbols(config :: map()) :: [String.t()]
```

### Multi-Symbol Support

Strategies can declare multiple symbols they need to subscribe to:

```elixir
# Helper function to get required symbols (Strategy module)
Strategy.get_required_symbols(strategy_module, config)
# => ["MDTUSDT", "AXLUSDT"]

# If strategy doesn't implement required_symbols/1, falls back to config["symbol"]
```

The Trader process subscribes to ticker streams for ALL returned symbols. Strategy filters ticks by current active symbol in `on_tick/2`.

### Requirements Declaration

```elixir
def requirements(_config) do
  %{
    ticks: true,        # Subscribe to market data ticks (default: true)
    timers: [],         # Timer intervals in ms, e.g., [60_000] for 1 minute
    executions: true    # Subscribe to execution reports (default: true)
  }
end
```

### Actions

Strategies return actions from callbacks:

```elixir
:noop                           # Do nothing
{:place_order, order_params}    # Place single order
{:place_order, [order1, order2]} # Place multiple orders
{:cancel_order, order_id}       # Cancel order (not fully implemented)
```

### Order Params Structure

```elixir
%{
  symbol: "BTCUSDT",
  side: "BUY" | "SELL",
  type: "MARKET" | "LIMIT",
  quantity: Decimal.t(),
  price: Decimal.t(),          # Required for LIMIT orders
  time_in_force: "GTC" | "IOC" | "FOK"  # For LIMIT orders
}
```

### Minimal Strategy Example

```elixir
defmodule TradingEngine.Strategies.Simple do
  @behaviour TradingEngine.Strategy

  @impl true
  def requirements(_config), do: %{ticks: true, timers: [], executions: true}

  @impl true
  def init(config) do
    {:ok, %{symbol: config["symbol"], last_price: nil}}
  end

  @impl true
  def on_tick(market_data, state) do
    price = Decimal.new(market_data["c"])
    # Your logic here
    {:noop, %{state | last_price: price}}
  end

  @impl true
  def on_execution(_execution, state) do
    {:noop, state}
  end
end
```

### Timer-Based Strategy Example (DCA-like)

```elixir
defmodule TradingEngine.Strategies.Periodic do
  @behaviour TradingEngine.Strategy

  @impl true
  def requirements(config) do
    interval = config["interval_ms"] || 3_600_000  # 1 hour default
    %{
      ticks: false,     # Don't need ticks
      timers: [interval],
      executions: true
    }
  end

  @impl true
  def init(config) do
    {:ok, %{symbol: config["symbol"], amount: config["amount"]}}
  end

  @impl true
  def on_timer(_ref, state) do
    # Fetch price via API since no tick subscription
    {:ok, price} = DataCollector.BinanceClient.get_ticker_price(state.symbol)
    quantity = Decimal.div(state.amount, Decimal.new(price["price"]))

    action = {:place_order, %{
      symbol: state.symbol,
      side: "BUY",
      type: "MARKET",
      quantity: quantity
    }}

    {action, state}
  end

  @impl true
  def on_tick(_market_data, state), do: {:noop, state}

  @impl true
  def on_execution(_execution, state), do: {:noop, state}
end
```

## Strategy Configurations

### Human-Readable Names (ВАЖНО!)

При создании стратегий **ВСЕГДА** добавляй поле `name` или `label` с понятным человеку описанием. Это критически важно для UI и отладки.

**Формат названия:**
```
[СИМВОЛ] [ДЕЙСТВИЕ] @ [ЦЕНА] → [ЦЕЛЬ]
```

**Примеры:**
```elixir
# ConditionalChain - single symbol (покупка с продажей)
%{
  "name" => "MDT: Buy 0.0153 → Sell 0.16",
  "symbol" => "MDTUSDT",
  ...
}

# ConditionalChain - multi-symbol chain (NEW!)
%{
  "name" => "MDT→AXL: Buy MDT 0.0153 → Sell 0.16 → Buy AXL 0.1440",
  "symbols" => ["MDTUSDT", "AXLUSDT"],
  ...
}

# ConditionalChain - только покупка
%{
  "name" => "AXL: Buy @ 0.1440",
  "symbol" => "AXLUSDT",
  ...
}

# Grid стратегия
%{
  "name" => "BTC Grid ±2% (5 levels, $50/grid)",
  "symbol" => "BTCUSDT",
  ...
}

# DCA стратегия
%{
  "name" => "ETH DCA $10/hour",
  "symbol" => "ETHUSDT",
  ...
}

# Naive стратегия
%{
  "name" => "DOT Scalp -1.2%/+2.2%",
  "symbol" => "DOTUSDT",
  ...
}
```

**Best Practices для названий:**
- Включай символ (без USDT суффикса для краткости)
- Указывай ключевые цены/проценты
- Для цепочек: показывай направление (Buy → Sell)
- Для multi-symbol: используй стрелку между символами (MDT→AXL)
- Для условий: указывай триггеры
- Максимум 40-50 символов

### Naive Strategy

Buy when price drops, sell when price rises.

```elixir
%{
  "symbol" => "BTCUSDT",
  "trade_amount" => 10,           # USDT amount per trade
  "buy_down_interval" => 0.012,   # Buy when price drops 1.2%
  "sell_up_interval" => 0.022     # Sell when price rises 2.2%
}
```

### Grid Strategy

Place grid of limit orders above and below current price.

```elixir
%{
  "symbol" => "BTCUSDT",
  "grid_levels" => 5,             # Number of grid levels
  "grid_spacing" => 0.005,        # 0.5% between levels
  "amount_per_grid" => 50         # USDT per grid level
}
```

### DCA Strategy

Dollar cost averaging - periodic fixed-amount buys.

```elixir
%{
  "symbol" => "BTCUSDT",
  "amount_per_buy" => 10,         # USDT per buy
  "interval_hours" => 24,         # Buy every 24 hours
  # OR
  "interval_minutes" => 60,       # Buy every hour
  # OR
  "interval_ms" => 3600000,       # Buy every hour (ms)
  "max_buys" => 100               # Maximum number of buys
}
```

### ConditionalChain Strategy

Sequential orders with conditional branching. Supports **multi-symbol chains** and **profit reinvestment**.

#### Single-Symbol Chain

```elixir
%{
  "name" => "BTC: Buy 45K → Sell 48K",
  "symbol" => "BTCUSDT",
  "initial_quantity" => "0.001",
  "steps" => [
    %{"type" => "initial", "side" => "BUY", "price" => "45000", "quantity" => "0.001"},
    %{"type" => "step", "side" => "SELL", "price" => "48000", "quantity" => "0.001"}
  ]
}
```

#### Multi-Symbol Chain (NEW!)

Execute orders across different symbols sequentially. Each step can have its own symbol:

```elixir
%{
  "name" => "MDT→AXL: Buy MDT 0.0153 → Sell 0.16 → Buy AXL 0.1440",
  "symbols" => ["MDTUSDT", "AXLUSDT"],  # All symbols for subscription
  "initial_quantity" => "6535.9",
  "steps" => [
    %{
      "type" => "initial",
      "symbol" => "MDTUSDT",           # Per-step symbol
      "side" => "BUY",
      "price" => "0.0153",
      "quantity" => "6535.9"           # ~100 USDT
    },
    %{
      "type" => "step",
      "symbol" => "MDTUSDT",
      "side" => "SELL",
      "price" => "0.16",
      "quantity" => "6535.9"           # ~1045 USDT profit
    },
    %{
      "type" => "step",
      "symbol" => "AXLUSDT",           # Different symbol!
      "side" => "BUY",
      "price" => "0.1440",
      "quantity" => "use_profit"       # Auto-calculate from sell proceeds
    }
  ]
}
```

#### `use_profit` Quantity

When `"quantity" => "use_profit"`, the strategy calculates quantity from the proceeds of the previous SELL:

```
proceeds (USDT) / target_price = quantity
1045.74 USDT / 0.1440 = 7262.08 AXL
```

#### Branching with Price Conditions

```elixir
%{
  "symbol" => "BTCUSDT",
  "branch_threshold_percent" => "1.0",  # ±1% triggers branch
  "steps" => [
    %{"type" => "initial", "side" => "BUY", "price" => "45000", "quantity" => "0.001"},
    %{
      "type" => "branch",
      "price_rises" => %{
        "side" => "SELL",
        "price" => "47000",
        "quantity" => "0.001"
      },
      "price_falls" => %{
        "side" => "BUY",
        "price" => "43000",
        "quantity" => "0.001"
      }
    }
  ]
}
```

#### State Lifecycle

- `:idle` - Initial state
- `:awaiting_initial` - Waiting for initial order fill
- `:awaiting_step` - Waiting for step order fill
- `:awaiting_branch` - Monitoring price for branch condition
- `:completed` - Chain finished
- `:error` - Error occurred

### Full Config with Conditions

```elixir
%{
  "symbol" => "BTCUSDT",
  "trade_amount" => 10,
  "buy_down_interval" => 0.01,
  "sell_up_interval" => 0.02,
  "start_conditions" => %{
    "logic" => "and",
    "conditions" => [
      %{"type" => "price", "operator" => "below", "value" => 50000},
      %{"type" => "time", "start_hour" => 9, "end_hour" => 17}
    ]
  },
  "stop_conditions" => %{
    "logic" => "or",
    "conditions" => [
      %{"type" => "take_profit", "percentage" => 5.0},
      %{"type" => "stop_loss", "percentage" => 2.0},
      %{"type" => "max_daily_loss", "amount" => 100}
    ]
  }
}
```

## Conditions System

### Start Conditions

Evaluated before strategy starts. Strategy waits in `PendingStrategiesManager` until met.

| Type | Config | Description |
|------|--------|-------------|
| `price` | `{"type": "price", "operator": "below"\|"above", "value": 50000}` | Price threshold |
| `time` | `{"type": "time", "start_hour": 9, "end_hour": 17, "timezone": "UTC"}` | Time window |
| `volume` | `{"type": "volume", "operator": "above"\|"below", "value": 1000000}` | Volume threshold |

### Stop Conditions

Evaluated while strategy is running. Triggers auto-stop when met.

| Type | Config | Description |
|------|--------|-------------|
| `take_profit` | `{"type": "take_profit", "percentage": 5.0}` | Stop when profit reaches X% |
| `stop_loss` | `{"type": "stop_loss", "percentage": 2.0}` | Stop when loss reaches X% |
| `max_daily_loss` | `{"type": "max_daily_loss", "amount": 100}` | Stop when daily loss exceeds amount |
| `time_stop` | `{"type": "time_stop", "duration_minutes": 60}` | Stop after X minutes |

### Condition Logic

```elixir
# AND logic - all conditions must be true
%{
  "logic" => "and",
  "conditions" => [condition1, condition2]
}

# OR logic - any condition triggers
%{
  "logic" => "or",
  "conditions" => [condition1, condition2]
}
```

## PubSub Events

### Topic: `strategy_updates`

Strategy lifecycle events. StrategyManager subscribes to this.

```elixir
# Strategy activated in UI/database
{:strategy_activated, setting}

# Strategy deactivated
{:strategy_deactivated, setting}

# Stop condition triggered
{:strategy_auto_stopped, setting, reason}

# Start condition met (from PendingStrategiesManager)
{:conditions_met, setting}
```

### Topic: `strategies:all`

For UI updates about strategy state.

```elixir
# Strategy successfully started
{:strategy_started, setting_id, %{strategy_name: "naive", account_id: id, config: config, started_at: datetime}}

# Strategy stopped
{:strategy_stopped, setting_id}

# Strategy error
{:strategy_error, setting_id, reason}
```

### Topic: `market:#{symbol}`

Market data from DataCollector.

```elixir
# Ticker update
{:ticker, %{"s" => "BTCUSDT", "c" => "45000.00", "v" => "1000.5", ...}}

# Trade update
{:trade, %{"s" => "BTCUSDT", "p" => "45000.00", "q" => "0.001", ...}}
```

### Topic: `order_updates`

Execution reports from Binance WebSocket.

```elixir
{:execution_report, %{
  "e" => "executionReport",
  "s" => "BTCUSDT",
  "S" => "BUY",
  "x" => "TRADE",        # Execution type: NEW, TRADE, CANCELED
  "X" => "FILLED",       # Order status
  "L" => "45000.00",     # Last executed price
  "l" => "0.001",        # Last executed quantity
  ...
}}
```

### Topic: `orders:#{account_id}`

Order lifecycle events for specific account.

```elixir
{:order_created, order}
{:order_filled, execution}
{:order_partially_filled, execution}
{:order_cancelled, execution}
```

### Topic: `position_updates`

Position changes from SharedPositionTracker.

```elixir
{:position_updated, account_id, symbol, %{
  quantity: Decimal.t(),
  avg_entry_price: Decimal.t(),
  realized_pnl: Decimal.t(),
  unrealized_pnl: Decimal.t()
}}
```

## IEx Debugging

### Check Running Strategies

```elixir
# List all running strategy IDs
TradingEngine.StrategyManager.get_running_strategies()

# Check specific strategy
TradingEngine.StrategyManager.is_running?("setting-uuid")
```

### Find Trader Process

```elixir
# Lookup by setting_id
Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
# => [{#PID<0.456.0>, nil}]

# Get process state
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
:sys.get_state(pid)
```

### Monitor PubSub Events

```elixir
# Subscribe to strategy events
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategy_updates")

# Subscribe to market data
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")

# Receive messages in IEx shell
flush()
```

### Check Positions

```elixir
# Get all positions
TradingEngine.SharedPositionTracker.get_all_positions()

# Get specific account positions
TradingEngine.SharedPositionTracker.get_account_positions("account-uuid")
```

### Check Pending Strategies

```elixir
# List pending (waiting for start conditions)
TradingEngine.PendingStrategiesManager.list_pending()

# Check if specific is pending
TradingEngine.PendingStrategiesManager.is_pending?("setting-uuid")
```

## Integration with Other Skills

| Skill | Use For |
|-------|---------|
| `binance-api` | Binance REST/WebSocket API, rate limiting, authentication |
| `elixir-otp` | GenServer patterns, supervision trees |
| `phoenix-liveview` | Building strategy management UI |
| `ecto-timescale` | Trade history storage, time-series queries |

## Key Files

| File | Description |
|------|-------------|
| `apps/trading_engine/lib/trading_engine/strategy.ex` | Strategy behaviour definition |
| `apps/trading_engine/lib/trading_engine/strategy_manager.ex` | Lifecycle management |
| `apps/trading_engine/lib/trading_engine/strategy_loader.ex` | Strategy registration |
| `apps/trading_engine/lib/trading_engine/trader.ex` | Strategy execution GenServer |
| `apps/trading_engine/lib/trading_engine/strategies/*.ex` | Built-in strategies |
| `apps/trading_engine/lib/trading_engine/conditions/*.ex` | Condition implementations |
| `apps/shared_data/lib/shared_data/settings.ex` | Settings context (activate/deactivate) |
