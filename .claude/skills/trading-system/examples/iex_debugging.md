# IEx Debugging Commands

Quick reference for debugging trading strategies in IEx console.

## Starting IEx

```bash
# With Phoenix server
make server-iex
# or
iex -S mix phx.server

# Without server (for debugging modules only)
iex -S mix
```

## Strategy Status

### List Running Strategies

```elixir
# Get all running strategy IDs
TradingEngine.StrategyManager.get_running_strategies()
# => ["abc-123", "def-456"]

# Check if specific strategy is running
TradingEngine.StrategyManager.is_running?("abc-123")
# => true
```

### Find Trader Process

```elixir
# Lookup process by setting_id
Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
# => [{#PID<0.456.0>, nil}]

# Get PID directly
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")

# Check if process is alive
Process.alive?(pid)
# => true
```

### Inspect Trader State

```elixir
# Get internal state of Trader GenServer
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
:sys.get_state(pid)
# => %{strategy_state: ..., account_id: ..., ...}

# Get strategy-specific state
state = :sys.get_state(pid)
state.strategy_state
```

## Pending Strategies

```elixir
# List strategies waiting for start conditions
TradingEngine.PendingStrategiesManager.list_pending()
# => ["setting-1", "setting-2"]

# Check if strategy is pending
TradingEngine.PendingStrategiesManager.is_pending?("setting-1")
# => true
```

## Position Tracking

```elixir
# Get all positions
TradingEngine.SharedPositionTracker.get_all_positions()
# => [{account_id, "BTCUSDT", %{quantity: ..., avg_price: ...}}, ...]

# Get positions for specific account
TradingEngine.SharedPositionTracker.get_account_positions("account-uuid")
# => [%{symbol: "BTCUSDT", quantity: ..., unrealized_pnl: ...}]

# Get single position
TradingEngine.SharedPositionTracker.get_position("account-uuid", "BTCUSDT")
# => %{quantity: Decimal, avg_entry_price: Decimal, ...}
```

## PubSub Monitoring

### Subscribe to Events

```elixir
# Strategy lifecycle events
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategy_updates")

# Market data for specific symbol
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")

# Order execution reports
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")

# Position changes
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "position_updates")

# All strategy state changes (for UI)
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategies:all")
```

### Receive Messages

```elixir
# After subscribing, use flush() to see messages
flush()
# {:ticker, %{"s" => "BTCUSDT", "c" => "45000.00", ...}}
# {:strategy_started, "setting-uuid", %{...}}

# Or receive in a loop
receive do
  {:ticker, data} -> IO.inspect(data, label: "Ticker")
  {:execution_report, data} -> IO.inspect(data, label: "Execution")
  msg -> IO.inspect(msg, label: "Other")
after
  5000 -> IO.puts("No message in 5 seconds")
end
```

## Manual Strategy Control

### Start Strategy Manually

```elixir
# Start by setting_id
TradingEngine.StrategyManager.start_strategy("setting-uuid")
# => {:ok, #PID<0.456.0>}
```

### Stop Strategy

```elixir
# Stop by setting_id
TradingEngine.StrategyManager.stop_strategy("setting-uuid")
# => :ok
```

### Create and Start Strategy

```elixir
# Create setting first
account = SharedData.Accounts.list_active_user_accounts(user_id) |> hd()

{:ok, setting} = SharedData.Settings.create_setting(%{
  account_id: account.id,
  strategy_name: "naive",
  config: %{
    "symbol" => "BTCUSDT",
    "trade_amount" => 10,
    "buy_down_interval" => 0.01,
    "sell_up_interval" => 0.02
  }
})

# Activate (triggers StrategyManager)
{:ok, _} = SharedData.Settings.activate_setting(setting)
```

## Database Queries

### Get Settings

```elixir
# Get all active settings
SharedData.Settings.list_active_settings()

# Get specific setting
SharedData.Settings.get_setting("setting-uuid")

# Get setting with credentials (for debugging)
SharedData.Settings.get_setting_with_credentials("setting-uuid")
```

### Get Orders

```elixir
# Recent orders for account
SharedData.Trading.list_account_orders("account-uuid")

# Active orders
SharedData.Trading.list_active_orders("account-uuid")
```

### Get Trades

```elixir
# Recent trades
SharedData.Trading.list_account_trades("account-uuid", limit: 10)

# Trades for symbol
SharedData.Trading.list_trades_by_symbol("account-uuid", "BTCUSDT", limit: 10)
```

## Strategy Testing

### Test Strategy Logic

```elixir
# Initialize strategy
config = %{"symbol" => "BTCUSDT", "trade_amount" => 10}
{:ok, state} = TradingEngine.Strategies.Naive.init(config)

# Simulate tick
market_data = %{"c" => "45000.00", "v" => "100.5"}
{action, new_state} = TradingEngine.Strategies.Naive.on_tick(market_data, state)

# Check action
IO.inspect(action)
# => :noop or {:place_order, %{...}}
```

### Test Conditions

```elixir
# Test condition evaluation
config = %{
  "logic" => "and",
  "conditions" => [
    %{"type" => "price", "operator" => "below", "value" => 50000}
  ]
}

{:ok, state} = TradingEngine.Conditions.ConditionEvaluator.init(config)

market_data = %{"c" => "49000.00"}
{met?, _new_state} = TradingEngine.Conditions.ConditionEvaluator.evaluate(config, market_data, state)
# => {true, ...}
```

## Binance API Testing

### Get Current Price

```elixir
DataCollector.BinanceClient.get_ticker_price("BTCUSDT")
# => {:ok, %{"symbol" => "BTCUSDT", "price" => "45000.00"}}
```

### Get Account Info

```elixir
# Need API credentials
api_key = "your_key"
secret_key = "your_secret"

DataCollector.BinanceClient.get_account(api_key, secret_key)
# => {:ok, %{"balances" => [...], ...}}
```

### Get Open Orders

```elixir
DataCollector.BinanceClient.get_open_orders(api_key, secret_key, "BTCUSDT")
# => {:ok, [%{"orderId" => ..., "status" => "NEW", ...}]}
```

## Process Inspection

### Get All Trader PIDs

```elixir
# List all registered traders
Registry.select(TradingEngine.TraderRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
# => [{"setting-1", #PID<0.456.0>}, {"setting-2", #PID<0.457.0>}]
```

### Monitor Process

```elixir
# Monitor a trader for crashes
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
ref = Process.monitor(pid)

# Will receive {:DOWN, ref, :process, pid, reason} if it crashes
```

### Send Message to Trader

```elixir
# Traders handle :get_state message (if implemented)
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, "setting-uuid")
GenServer.call(pid, :get_state)
```

## Troubleshooting

### Strategy Won't Start

```elixir
# Check if setting exists and is active
setting = SharedData.Settings.get_setting("setting-uuid")
IO.inspect(setting.is_active, label: "Is Active")

# Check if credentials exist
setting = SharedData.Settings.get_setting_with_credentials("setting-uuid")
IO.inspect(setting.account.api_credential != nil, label: "Has Credentials")

# Check strategy is valid
TradingEngine.StrategyLoader.valid_strategy?(setting.strategy_name)
```

### No Market Data

```elixir
# Check WebSocket status
# Subscribe and check if receiving
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")

# Wait for tick
receive do
  {:ticker, data} -> IO.inspect(data)
after
  10000 -> IO.puts("No ticker in 10 seconds - WebSocket may be down")
end
```

### Memory/Process Issues

```elixir
# Check running processes count
length(Process.list())

# Check ETS tables
:ets.all() |> length()

# Memory usage
:erlang.memory()
```
