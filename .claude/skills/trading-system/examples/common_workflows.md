# Common Workflows

Step-by-step guides for common trading system tasks.

## Creating a New Strategy

### 1. Use the Generator Script

```bash
# Interactive mode
python3 .claude/skills/trading-system/scripts/generate_strategy.py

# With parameters
python3 .claude/skills/trading-system/scripts/generate_strategy.py \
  --name momentum \
  --type tick \
  --description "Momentum-based trading strategy"
```

### 2. Implement Strategy Logic

Edit the generated file at `apps/trading_engine/lib/trading_engine/strategies/momentum.ex`:

```elixir
@impl true
def on_tick(market_data, state) do
  current_price = Decimal.new(market_data["c"])

  # Your logic here
  cond do
    should_buy?(current_price, state) ->
      {:place_order, %{symbol: state.symbol, side: "BUY", type: "MARKET", quantity: state.qty}}

    should_sell?(current_price, state) ->
      {:place_order, %{symbol: state.symbol, side: "SELL", type: "MARKET", quantity: state.qty}}

    true ->
      :noop
  end
  |> then(fn action -> {action, %{state | last_price: current_price}} end)
end
```

### 3. Register in StrategyLoader

If the generator didn't update automatically, add to `apps/trading_engine/lib/trading_engine/strategy_loader.ex`:

```elixir
@strategies %{
  "naive" => TradingEngine.Strategies.Naive,
  "grid" => TradingEngine.Strategies.Grid,
  "dca" => TradingEngine.Strategies.DCA,
  "conditional_chain" => TradingEngine.Strategies.ConditionalChain,
  "momentum" => TradingEngine.Strategies.Momentum  # Add here
}
```

### 4. Test in IEx

```elixir
# Test initialization
config = %{"symbol" => "BTCUSDT", "your_param" => "value"}
{:ok, state} = TradingEngine.Strategies.Momentum.init(config)

# Test tick handling
market_data = %{"c" => "45000.00", "v" => "100"}
{action, new_state} = TradingEngine.Strategies.Momentum.on_tick(market_data, state)
```

### 5. Create Setting in Database

```elixir
# In IEx
account = SharedData.Accounts.list_active_user_accounts(user_id) |> hd()

{:ok, setting} = SharedData.Settings.create_setting(%{
  account_id: account.id,
  strategy_name: "momentum",
  config: %{
    "symbol" => "BTCUSDT",
    "your_param" => "value"
  }
})
```

---

## Setting Up a Strategy with Conditions

### Start Conditions

Strategy waits until conditions are met before starting:

```elixir
config = %{
  "symbol" => "BTCUSDT",
  "trade_amount" => 10,
  "buy_down_interval" => 0.01,
  "sell_up_interval" => 0.02,

  "start_conditions" => %{
    "logic" => "and",  # All conditions must be true
    "conditions" => [
      # Only start when price is below 50000
      %{"type" => "price", "operator" => "below", "value" => 50000},
      # Only during trading hours (9 AM - 5 PM UTC)
      %{"type" => "time", "start_hour" => 9, "end_hour" => 17}
    ]
  }
}

{:ok, setting} = SharedData.Settings.create_setting(%{
  account_id: account.id,
  strategy_name: "naive",
  config: config
})

# Activate - will go to PendingStrategiesManager
{:ok, _} = SharedData.Settings.activate_setting(setting)

# Check pending status
TradingEngine.PendingStrategiesManager.is_pending?(setting.id)
# => true
```

### Stop Conditions

Strategy auto-stops when conditions are met:

```elixir
config = %{
  "symbol" => "BTCUSDT",
  "trade_amount" => 10,

  "stop_conditions" => %{
    "logic" => "or",  # Any condition triggers stop
    "conditions" => [
      # Take profit at 5%
      %{"type" => "take_profit", "percentage" => 5.0},
      # Stop loss at 2%
      %{"type" => "stop_loss", "percentage" => 2.0},
      # Stop if daily loss exceeds 100 USDT
      %{"type" => "max_daily_loss", "amount" => 100},
      # Stop after 24 hours
      %{"type" => "time_stop", "duration_minutes" => 1440}
    ]
  }
}
```

---

## Monitoring Running Strategies

### Via IEx Console

```elixir
# Get all running strategies
running = TradingEngine.StrategyManager.get_running_strategies()

# For each running strategy, get details
Enum.each(running, fn setting_id ->
  setting = SharedData.Settings.get_setting(setting_id)
  position = TradingEngine.SharedPositionTracker.get_position(
    setting.account_id,
    setting.config["symbol"]
  )

  IO.puts("Strategy: #{setting.strategy_name}")
  IO.puts("  Symbol: #{setting.config["symbol"]}")
  IO.puts("  Position: #{inspect(position)}")
  IO.puts("")
end)
```

### Via PubSub

```elixir
# Subscribe to all strategy events
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategies:all")

# Monitor in a loop
spawn(fn ->
  receive do
    {:strategy_started, id, meta} ->
      IO.puts("Started: #{id} - #{meta.strategy_name}")
    {:strategy_stopped, id} ->
      IO.puts("Stopped: #{id}")
    {:strategy_error, id, reason} ->
      IO.puts("Error: #{id} - #{inspect(reason)}")
  end
end)
```

---

## Stopping All Strategies for an Account

```elixir
# Get all settings for account
settings = SharedData.Settings.list_settings_by_account(account_id)

# Deactivate each one
Enum.each(settings, fn setting ->
  if setting.is_active do
    SharedData.Settings.deactivate_setting(setting)
    IO.puts("Deactivated: #{setting.id}")
  end
end)

# Verify all stopped
TradingEngine.StrategyManager.get_running_strategies()
# Should not contain any settings from this account
```

---

## Debugging a Stuck Strategy

### 1. Check if Running

```elixir
setting_id = "your-setting-uuid"

TradingEngine.StrategyManager.is_running?(setting_id)
```

### 2. Check if Pending

```elixir
TradingEngine.PendingStrategiesManager.is_pending?(setting_id)
```

### 3. Find Process

```elixir
Registry.lookup(TradingEngine.TraderRegistry, setting_id)
# => [{#PID<0.456.0>, nil}] or []
```

### 4. Inspect State

```elixir
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, setting_id)
state = :sys.get_state(pid)

IO.inspect(state.strategy_state, label: "Strategy State")
```

### 5. Check Market Data Flow

```elixir
# Subscribe to market data
symbol = state.strategy_state.symbol
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")

# Wait for tick
receive do
  {:ticker, data} -> IO.inspect(data)
after
  10000 -> IO.puts("No data in 10 seconds")
end
```

### 6. Force Stop if Needed

```elixir
TradingEngine.StrategyManager.stop_strategy(setting_id)

# Or kill the process directly
[{pid, _}] = Registry.lookup(TradingEngine.TraderRegistry, setting_id)
Process.exit(pid, :kill)
```

---

## Adding Custom Condition Type

### 1. Create Condition Module

```elixir
defmodule TradingEngine.Conditions.RSICondition do
  @behaviour TradingEngine.Conditions.Condition

  @impl true
  def type, do: :start  # or :stop

  @impl true
  def init(config) do
    {:ok, %{
      threshold: config["threshold"] || 30,
      operator: config["operator"] || "below"
    }}
  end

  @impl true
  def evaluate(market_data, state) do
    # Calculate RSI from market_data
    rsi = calculate_rsi(market_data)

    met? = case state.operator do
      "below" -> rsi < state.threshold
      "above" -> rsi > state.threshold
      _ -> false
    end

    {met?, state}
  end

  @impl true
  def describe(state) do
    "RSI #{state.operator} #{state.threshold}"
  end

  defp calculate_rsi(_market_data) do
    # Your RSI calculation
    50.0
  end
end
```

### 2. Register at Runtime

```elixir
TradingEngine.Conditions.ConditionEvaluator.register_condition(
  "rsi",
  TradingEngine.Conditions.RSICondition
)
```

### 3. Use in Config

```elixir
%{
  "start_conditions" => %{
    "logic" => "and",
    "conditions" => [
      %{"type" => "rsi", "operator" => "below", "threshold" => 30}
    ]
  }
}
```

---

## Testing Strategy in Dev Environment

### 1. Use Testnet

Ensure `.env` has testnet configuration:

```bash
BINANCE_BASE_URL=https://testnet.binance.vision
```

### 2. Create Test Account

```elixir
# Create user if needed
{:ok, user} = SharedData.Accounts.create_user(%{
  email: "test@example.com",
  password: "password123",
  password_confirmation: "password123"
})

# Add testnet credentials
{:ok, credential} = SharedData.Credentials.create_credential(%{
  user_id: user.id,
  api_key: "your_testnet_key",
  secret_key: "your_testnet_secret",
  label: "Testnet",
  is_testnet: true
})

# Create account
{:ok, account} = SharedData.Accounts.create_account(user.id, %{
  api_credential_id: credential.id,
  label: "Test Account"
})
```

### 3. Run Strategy with Small Amounts

```elixir
{:ok, setting} = SharedData.Settings.create_setting(%{
  account_id: account.id,
  strategy_name: "naive",
  config: %{
    "symbol" => "BTCUSDT",
    "trade_amount" => 10  # Small amount for testing
  }
})

SharedData.Settings.activate_setting(setting)
```

### 4. Monitor Execution

```elixir
# Subscribe to events
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "orders:#{account.id}")
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")

# Watch for activity
flush()
```

---

## Restarting After Crash

The system automatically restores active strategies on startup, but if you need to manually restore:

```elixir
# Get all active settings
active = SharedData.Settings.list_active_settings()

# Check which are running
running = TradingEngine.StrategyManager.get_running_strategies() |> MapSet.new()

# Find not running
not_running = Enum.reject(active, fn s -> MapSet.member?(running, s.id) end)

# Start them
Enum.each(not_running, fn setting ->
  case TradingEngine.StrategyManager.start_strategy(setting.id) do
    {:ok, _pid} -> IO.puts("Started: #{setting.id}")
    {:error, reason} -> IO.puts("Failed: #{setting.id} - #{inspect(reason)}")
  end
end)
```
