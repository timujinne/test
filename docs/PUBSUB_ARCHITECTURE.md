# PubSub Architecture

## Overview

Binance Trading System uses a **single** `Phoenix.PubSub` instance named `BinanceSystem.PubSub` across all applications in the umbrella project.

## Architecture Decision

**Why single PubSub?**
- Simplifies inter-app communication
- Reduces resource usage
- Avoids message routing complexity
- Ensures consistent pub/sub behavior

## Initialization

The PubSub instance is started in `DataCollector.Application`:

```elixir
# apps/data_collector/lib/data_collector/application.ex
def start(_type, _args) do
  children = [
    DataCollector.RateLimiter,
    DataCollector.MarketData,
    {Phoenix.PubSub, name: BinanceSystem.PubSub}
  ]
  # ...
end
```

## Centralized Access

All applications should use `SharedData.PubSub` module for type-safe access:

```elixir
# Subscribe
SharedData.PubSub.subscribe("market:BTCUSDT")

# Broadcast
SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, data})

# Get PubSub name
pubsub = SharedData.PubSub.name()
```

## Topics Structure

### Market Data Topics

#### `market:#{symbol}`
Real-time market data for a specific trading symbol.

**Publishers:**
- `DataCollector.BinanceWebSocket`

**Subscribers:**
- `DataCollector.MarketData` - Caches price data in ETS
- `TradingEngine.Trader` - Passes to strategy for decision making
- `DashboardWeb.TradingLive` - Updates UI

**Message Types:**
```elixir
{:ticker, %{
  "e" => "24hrTicker",
  "s" => "BTCUSDT",
  "c" => "50000.00",  # Current price
  "h" => "51000.00",  # High price
  "l" => "49000.00",  # Low price
  # ... more fields
}}

{:trade, %{
  "e" => "trade",
  "s" => "BTCUSDT",
  "p" => "50000.00",  # Price
  "q" => "0.001",     # Quantity
  "T" => 1234567890,  # Trade time
  # ... more fields
}}
```

### Trading Update Topics

#### `order_updates`
Order execution reports from Binance.

**Publishers:**
- `DataCollector.BinanceWebSocket`

**Subscribers:**
- `TradingEngine.Trader` - Updates strategy state
- `DashboardWeb.TradingLive` - Updates order list

**Message Types:**
```elixir
{:execution_report, %{
  "e" => "executionReport",
  "s" => "BTCUSDT",
  "i" => 12345,           # Order ID
  "X" => "FILLED",        # Order status
  "S" => "BUY",           # Side
  "p" => "50000.00",      # Price
  "q" => "0.001",         # Quantity
  "L" => "50000.00",      # Last executed price
  "l" => "0.001",         # Last executed quantity
  "a" => 1,               # Account ID
  # ... more fields
}}
```

#### `balance_updates`
Account balance changes.

**Publishers:**
- `DataCollector.BinanceWebSocket`

**Subscribers:**
- `DashboardWeb.PortfolioLive` - Updates balance display

**Message Types:**
```elixir
{:balance_update, %{
  "e" => "outboundAccountPosition",
  "B" => [
    %{
      "a" => "BTC",
      "f" => "1.000000",    # Free
      "l" => "0.000000"     # Locked
    },
    # ... more balances
  ]
}}
```

## Topic Naming Conventions

1. **Market data**: `market:#{symbol}` (e.g., `market:BTCUSDT`)
2. **Trading updates**: `order_updates`, `balance_updates`
3. **Future topics**:
   - `account:#{account_id}` - Account-specific events
   - `strategy:#{strategy_name}` - Strategy-specific events
   - `alerts:#{type}` - System alerts

## Message Flow Example

### Order Placement Flow

```
User Action (LiveView)
  ↓
TradingEngine.Trader (place_order)
  ↓
DataCollector.BinanceClient (create_order API call)
  ↓
Binance API
  ↓
WebSocket execution report
  ↓
DataCollector.BinanceWebSocket
  ↓ (broadcast)
SharedData.PubSub ["order_updates"]
  ↓ (subscribed)
  ├─→ TradingEngine.Trader (updates strategy)
  └─→ DashboardWeb.TradingLive (updates UI)
```

### Market Data Flow

```
Binance WebSocket Stream
  ↓
DataCollector.BinanceWebSocket
  ↓ (broadcast)
SharedData.PubSub ["market:BTCUSDT"]
  ↓ (subscribed)
  ├─→ DataCollector.MarketData (cache in ETS)
  ├─→ TradingEngine.Trader (strategy decision)
  └─→ DashboardWeb.TradingLive (UI update)
```

## Best Practices

### 1. Use Centralized Module
```elixir
# ✅ Good
SharedData.PubSub.subscribe("market:BTCUSDT")

# ❌ Avoid (but works)
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
```

### 2. Pattern Match Messages
```elixir
def handle_info({:ticker, %{"s" => symbol, "c" => price}}, socket) do
  # Handle ticker update
end

def handle_info({:execution_report, %{"X" => "FILLED"} = execution}, state) do
  # Handle filled order
end
```

### 3. Subscribe in init/mount
```elixir
# GenServer
def init(opts) do
  symbol = Keyword.fetch!(opts, :symbol)
  SharedData.PubSub.subscribe("market:#{symbol}")
  {:ok, %{symbol: symbol}}
end

# LiveView
def mount(_params, _session, socket) do
  if connected?(socket) do
    SharedData.PubSub.subscribe("order_updates")
  end
  {:ok, socket}
end
```

### 4. Unsubscribe on Cleanup
```elixir
def terminate(_reason, state) do
  SharedData.PubSub.unsubscribe("market:#{state.symbol}")
  :ok
end
```

## Monitoring

### Metrics to Track

1. **Message Rate** - Messages/second per topic
2. **Subscriber Count** - Active subscribers per topic
3. **Message Latency** - Time from publish to receive
4. **Failed Deliveries** - Messages that couldn't be delivered

### Example Telemetry

```elixir
:telemetry.execute(
  [:pubsub, :broadcast],
  %{count: 1, latency: latency_ms},
  %{topic: topic, message_type: type}
)
```

## Troubleshooting

### Issue: Messages not received

**Checklist:**
1. Is process subscribed? Check with `:sys.get_state(pid)`
2. Is PubSub running? Check `Supervisor.which_children(DataCollector.Supervisor)`
3. Is topic name correct? Check for typos
4. Is handle_info defined? Check for pattern match

### Issue: Duplicate messages

**Possible causes:**
1. Multiple subscriptions to same topic
2. Multiple PubSub instances (should not happen now)
3. Broadcasting in loop without guard

### Issue: Memory leak

**Possible causes:**
1. Not unsubscribing on process termination
2. Too many messages queued (slow consumer)
3. Large message payloads

**Solution:**
```elixir
def terminate(_reason, state) do
  # Always unsubscribe
  SharedData.PubSub.unsubscribe("market:#{state.symbol}")
  :ok
end
```

## Testing

### Unit Tests

```elixir
test "broadcasts ticker update" do
  SharedData.PubSub.subscribe("market:BTCUSDT")

  ticker = %{"s" => "BTCUSDT", "c" => "50000"}
  SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, ticker})

  assert_receive {:ticker, ^ticker}
end
```

### Integration Tests

```elixir
test "trader receives market data and updates strategy" do
  {:ok, trader} = Trader.start_link(account_id: 1, symbol: "BTCUSDT")

  # Simulate WebSocket message
  SharedData.PubSub.broadcast("market:BTCUSDT", {:ticker, %{"c" => "50000"}})

  # Wait for trader to process
  Process.sleep(100)

  state = Trader.get_state(1)
  assert state.last_price == Decimal.new("50000")
end
```

## Future Improvements

1. **Message Schemas** - Validate message structure with schemas
2. **Message Versioning** - Support different message versions
3. **Message Replay** - Store and replay messages for debugging
4. **Distributed PubSub** - Support multi-node deployments with Phoenix.PubSub.PG2
5. **Message Encryption** - Encrypt sensitive messages (API keys, balances)

## References

- [Phoenix.PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/)
- [Phoenix LiveView PubSub](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-pubsub)
- [Elixir Process Groups](https://hexdocs.pm/elixir/Registry.html)
