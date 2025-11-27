# WebSocket Streams Usage Guide

This document provides examples of how to use the new DepthStream and KlineStream modules.

## DepthStream - Order Book Updates

### Starting the Stream

```elixir
# Start a depth stream for BTCUSDT
{:ok, pid} = DataCollector.DepthStream.start_link(symbol: "BTCUSDT")
```

### Subscribing to Updates

```elixir
# Subscribe to depth updates
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "depth:BTCUSDT")

# Receive messages
def handle_info({:depth_update, update}, state) do
  # update = %{
  #   bids: [{price, quantity}, ...],     # List of bid levels
  #   asks: [{price, quantity}, ...],     # List of ask levels
  #   update_id: 160,                     # Final update ID
  #   first_update_id: 157,               # First update ID
  #   event_time: 123456789               # Timestamp
  # }

  best_bid = update.bids |> List.first() |> elem(0)
  best_ask = update.asks |> List.first() |> elem(0)
  spread = best_ask - best_bid

  Logger.info("Spread: #{spread}")
  {:noreply, state}
end
```

### Looking up Process

```elixir
# Find the depth stream process via Registry
pid = GenServer.whereis(DataCollector.DepthStream.via_tuple("BTCUSDT"))
```

## KlineStream - Candlestick Updates

### Starting the Stream

```elixir
# Start a 1-hour kline stream for BTCUSDT
{:ok, pid} = DataCollector.KlineStream.start_link(symbol: "BTCUSDT", interval: "1h")

# Start a 5-minute kline stream
{:ok, pid} = DataCollector.KlineStream.start_link(symbol: "ETHUSDT", interval: "5m")
```

### Valid Intervals

- Minutes: `1m`, `3m`, `5m`, `15m`, `30m`
- Hours: `1h`, `2h`, `4h`, `6h`, `8h`, `12h`
- Days: `1d`, `3d`
- Weeks: `1w`
- Months: `1M`

### Subscribing to Updates

```elixir
# Subscribe to kline updates
Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "kline:BTCUSDT:1h")

# Receive messages
def handle_info({:kline_update, candle}, state) do
  # candle = %{
  #   time: 123400000,              # Kline start time (unix timestamp ms)
  #   close_time: 123460000,        # Kline close time
  #   open: 50000.0,                # Open price
  #   high: 51000.0,                # High price
  #   low: 49500.0,                 # Low price
  #   close: 50500.0,               # Close price
  #   volume: 1234.56,              # Base asset volume
  #   quote_volume: 62345678.90,    # Quote asset volume
  #   trades: 1500,                 # Number of trades
  #   closed: false,                # Is this kline closed?
  #   interval: "1h"                # Interval
  # }

  if candle.closed do
    # Only process completed candles
    Logger.info("Closed candle: O:#{candle.open} H:#{candle.high} L:#{candle.low} C:#{candle.close}")
  end

  {:noreply, state}
end
```

### Looking up Process

```elixir
# Find the kline stream process via Registry
pid = GenServer.whereis(DataCollector.KlineStream.via_tuple("BTCUSDT", "1h"))
```

## Using in a Supervisor

### Starting Streams as Children

```elixir
defmodule MyApp.StreamSupervisor do
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      # Depth streams
      {DataCollector.DepthStream, symbol: "BTCUSDT"},
      {DataCollector.DepthStream, symbol: "ETHUSDT"},

      # Kline streams - multiple intervals
      {DataCollector.KlineStream, symbol: "BTCUSDT", interval: "1m"},
      {DataCollector.KlineStream, symbol: "BTCUSDT", interval: "1h"},
      {DataCollector.KlineStream, symbol: "ETHUSDT", interval: "5m"}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Dynamic Stream Management

```elixir
defmodule MyApp.StreamManager do
  @moduledoc """
  Dynamically start and stop WebSocket streams.
  """

  def start_depth_stream(symbol) do
    child_spec = {DataCollector.DepthStream, symbol: symbol}
    DynamicSupervisor.start_child(MyApp.DynamicStreamSupervisor, child_spec)
  end

  def start_kline_stream(symbol, interval) do
    child_spec = {DataCollector.KlineStream, symbol: symbol, interval: interval}
    DynamicSupervisor.start_child(MyApp.DynamicStreamSupervisor, child_spec)
  end

  def stop_depth_stream(symbol) do
    case GenServer.whereis(DataCollector.DepthStream.via_tuple(symbol)) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(MyApp.DynamicStreamSupervisor, pid)
    end
  end

  def stop_kline_stream(symbol, interval) do
    case GenServer.whereis(DataCollector.KlineStream.via_tuple(symbol, interval)) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(MyApp.DynamicStreamSupervisor, pid)
    end
  end
end
```

## Integration Example: Trading Strategy

```elixir
defmodule MyApp.TradingStrategy do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    symbol = Keyword.fetch!(opts, :symbol)

    # Subscribe to both depth and kline streams
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "depth:#{symbol}")
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "kline:#{symbol}:1m")

    state = %{
      symbol: symbol,
      last_candle: nil,
      order_book: %{bids: [], asks: []}
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:depth_update, update}, state) do
    # Update order book
    new_state = %{state | order_book: %{bids: update.bids, asks: update.asks}}

    # Calculate spread
    [{best_bid, _} | _] = update.bids
    [{best_ask, _} | _] = update.asks
    spread = best_ask - best_bid

    Logger.debug("Spread: #{spread}")

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:kline_update, candle}, state) do
    # Only process closed candles for signals
    if candle.closed do
      new_state = %{state | last_candle: candle}

      # Generate trading signals based on candle and order book
      check_trading_signals(new_state)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  defp check_trading_signals(state) do
    # Your trading logic here
    # Use state.last_candle and state.order_book to make decisions
    :ok
  end
end
```

## Error Handling and Reconnection

Both `DepthStream` and `KlineStream` implement automatic reconnection with exponential backoff:

- **Initial backoff**: 1 second
- **Max backoff**: 5 minutes
- **Backoff multiplier**: 2x
- **Max reconnect attempts**: 10
- **Jitter**: ±20% to prevent thundering herd

The streams will automatically reconnect on disconnection and continue from where they left off. No manual intervention is required.

## Performance Considerations

1. **Update Frequency**: DepthStream uses `@100ms` for fast updates. For slower updates, you can modify the stream to use `@1000ms`.

2. **Multiple Intervals**: You can run multiple KlineStreams for the same symbol with different intervals without conflicts.

3. **Registry**: All streams are registered in `DataCollector.StreamRegistry` for easy lookup and process management.

4. **PubSub**: Both streams use Phoenix.PubSub for broadcasting, allowing multiple subscribers per stream.

## Debugging

Enable debug logging to see stream activity:

```elixir
# In config/dev.exs
config :logger, level: :debug

# You'll see messages like:
# [debug] DepthStream (BTCUSDT): Broadcasting depth update (5 bids, 5 asks)
# [debug] KlineStream (BTCUSDT/1h): Broadcasting kline update (closed: false)
```
