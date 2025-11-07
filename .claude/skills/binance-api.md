---
name: binance-api
description: Complete guide for integrating with Binance REST and WebSocket APIs in Elixir applications. This skill should be used when implementing cryptocurrency trading systems, market data streaming, order management, or any Binance exchange integration requiring proper rate limiting, authentication, and error handling.
---

# Binance API Integration

This skill provides comprehensive guidance for integrating Binance cryptocurrency exchange APIs in Elixir applications.

## When to Use This Skill

Use this skill when:
- Implementing Binance REST API clients
- Setting up WebSocket market data streams
- Building trading bots or automated trading systems
- Managing API rate limits and quotas
- Handling Binance API authentication (HMAC signatures)
- Implementing reconnection strategies for WebSocket streams
- Debugging Binance API errors and responses

## Binance API Fundamentals

### Available Elixir Libraries

**Recommended libraries:**

1. **dvcrn/binance.ex** (Most popular, 21k+ downloads)
```elixir
# mix.exs
{:binance, "~> 2.0.1"}

# Basic usage
Binance.Market.get_ticker_price()
# => {:ok, [%Binance.Structs.SymbolPrice{symbol: "ETHBTC", price: "0.06275000"}, ...]}

Binance.Trade.post_order("BNBUSDT", "BUY", "MARKET", quantity: 0.01)
```

2. **MikaAK/binance-api-elixir** (Futures support)
```elixir
# config/config.exs
config :binance_api,
  api_key: System.get_env("BINANCE_API_KEY"),
  secret_key: System.get_env("BINANCE_SECRET_KEY"),
  base_url: "https://api.binance.com",
  base_futures_url: "https://fapi.binance.com"
```

### API Endpoints

**Spot Trading:**
- Base URL: `https://api.binance.com`
- WebSocket: `wss://stream.binance.com:9443`

**Futures:**
- Base URL: `https://fapi.binance.com`
- WebSocket: `wss://fstream.binance.com`

**Testnet (for development):**
- Spot: `https://testnet.binance.vision`
- Futures: `https://testnet.binancefuture.com`

## Rate Limiting

### Understanding Binance Rate Limits

Binance enforces multiple rate limit types:

1. **REQUEST_WEIGHT** (most common)
   - Limit: 6,000 weight units per minute per IP
   - Each endpoint has a weight (1-50)
   - Example: Getting ticker price = 2 weight

2. **ORDERS**
   - 50 orders per 10 seconds per account
   - 160,000 orders per 24 hours per account

3. **RAW_REQUESTS**
   - Maximum number of raw requests
   - Less common, usually higher limits

### Implementing Rate Limiter

**GenServer-based rate limiter:**

```elixir
defmodule BinanceRateLimiter do
  use GenServer
  require Logger

  @weight_limit 6000
  @weight_interval 60_000  # 1 minute
  @order_limit_10s 50
  @order_limit_24h 160_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if request can proceed and increment counters"
  def check_and_increment(type, weight \\ 1) do
    GenServer.call(__MODULE__, {:check, type, weight})
  end

  def init(_opts) do
    # Start cleanup timer
    schedule_cleanup()
    
    {:ok, %{
      weight_used: 0,
      weight_reset_at: System.monotonic_time(:millisecond) + @weight_interval,
      orders_10s: [],
      orders_24h: []
    }}
  end

  def handle_call({:check, :weight, weight}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    # Reset if interval passed
    state = if now >= state.weight_reset_at do
      %{state | 
        weight_used: 0,
        weight_reset_at: now + @weight_interval
      }
    else
      state
    end
    
    if state.weight_used + weight <= @weight_limit do
      new_state = %{state | weight_used: state.weight_used + weight}
      {:reply, :ok, new_state}
    else
      wait_time = state.weight_reset_at - now
      {:reply, {:error, {:rate_limited, wait_time}}, state}
    end
  end

  def handle_call({:check, :order, _weight}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    # Clean old orders
    orders_10s = Enum.filter(state.orders_10s, &(&1 > now - 10_000))
    orders_24h = Enum.filter(state.orders_24h, &(&1 > now - 86_400_000))
    
    cond do
      length(orders_10s) >= @order_limit_10s ->
        {:reply, {:error, :rate_limited_10s}, state}
      
      length(orders_24h) >= @order_limit_24h ->
        {:reply, {:error, :rate_limited_24h}, state}
      
      true ->
        new_state = %{state |
          orders_10s: [now | orders_10s],
          orders_24h: [now | orders_24h]
        }
        {:reply, :ok, new_state}
    end
  end

  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    
    # Clean old order records
    orders_10s = Enum.filter(state.orders_10s, &(&1 > now - 10_000))
    orders_24h = Enum.filter(state.orders_24h, &(&1 > now - 86_400_000))
    
    schedule_cleanup()
    {:noreply, %{state | orders_10s: orders_10s, orders_24h: orders_24h}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 10_000)  # Every 10 seconds
  end
end
```

### Monitoring Rate Limits from Response Headers

Binance returns rate limit info in response headers:

```elixir
defmodule BinanceClient do
  def make_request(url, headers \\ []) do
    case HTTPoison.get(url, headers) do
      {:ok, %{headers: response_headers, body: body}} ->
        # Parse rate limit headers
        weight_used = get_header(response_headers, "x-mbx-used-weight-1m")
        order_count = get_header(response_headers, "x-mbx-order-count-10s")
        
        Logger.info("Rate limits - Weight: #{weight_used}/6000, Orders: #{order_count}/50")
        
        {:ok, Jason.decode!(body)}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_header(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> "0"
    end
  end
end
```

### Handling Rate Limit Errors

**Error codes:**
- **429**: Rate limit exceeded, use `Retry-After` header
- **418**: IP banned (2 minutes to 3 days depending on violations)

```elixir
def handle_api_error({:error, %{status_code: 429, headers: headers}}) do
  retry_after = get_retry_after(headers)
  Logger.warn("Rate limited, retry after #{retry_after}ms")
  
  Process.sleep(retry_after)
  # Retry request
end

def handle_api_error({:error, %{status_code: 418}}) do
  Logger.error("IP banned by Binance!")
  # Alert administrators, switch to backup IP
  {:error, :ip_banned}
end
```

## Authentication and Security

### HMAC SHA256 Signatures

Binance requires HMAC signatures for authenticated endpoints:

```elixir
defmodule BinanceAuth do
  def sign_request(params, secret_key) do
    query_string = URI.encode_query(params)
    signature = :crypto.mac(:hmac, :sha256, secret_key, query_string)
                |> Base.encode16(case: :lower)
    
    Map.put(params, :signature, signature)
  end

  def timestamp do
    System.system_time(:millisecond)
  end

  def authenticated_request(url, params, api_key, secret_key) do
    # Add timestamp
    params = Map.put(params, :timestamp, timestamp())
    
    # Sign request
    signed_params = sign_request(params, secret_key)
    
    # Make request
    headers = [
      {"X-MBX-APIKEY", api_key},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
    
    HTTPoison.post(url, URI.encode_query(signed_params), headers)
  end
end
```

### Secure Credential Management

**Never hardcode API keys. Use runtime configuration:**

```elixir
# config/runtime.exs
config :my_app, BinanceClient,
  api_key: System.fetch_env!("BINANCE_API_KEY"),
  api_secret: System.fetch_env!("BINANCE_API_SECRET")

# Usage with encryption (see elixir-security skill)
defmodule MyApp.BinanceClient do
  def init(account_id) do
    credentials = load_encrypted_credentials(account_id)
    
    client = %{
      api_key: decrypt(credentials.api_key),
      api_secret: decrypt(credentials.api_secret),
      account_id: account_id
    }
    
    {:ok, client}
  end
end
```

## WebSocket Streams

### Stream Types

1. **Trade Streams** - Real-time trade data
   - `wss://stream.binance.com:9443/ws/btcusdt@trade`

2. **Kline/Candlestick** - OHLCV data
   - `wss://stream.binance.com:9443/ws/btcusdt@kline_1m`

3. **Depth Streams** - Order book updates
   - `wss://stream.binance.com:9443/ws/btcusdt@depth`
   - `wss://stream.binance.com:9443/ws/btcusdt@depth@100ms` (100ms updates)

4. **User Data Streams** - Account updates, orders
   - Requires listen key from REST API

### WebSocket Implementation with WebSockex

```elixir
# mix.exs
{:websockex, "~> 0.4.3"}

defmodule BinanceWebSocket do
  use WebSockex
  require Logger

  @base_url "wss://stream.binance.com:9443/ws"

  def start_link(symbol, stream_type \\ :trade) do
    symbol_lower = String.downcase(symbol)
    url = "#{@base_url}/#{symbol_lower}@#{stream_type}"
    
    WebSockex.start_link(url, __MODULE__, %{
      symbol: symbol,
      stream_type: stream_type,
      retry_count: 0
    }, name: via_tuple(symbol, stream_type))
  end

  defp via_tuple(symbol, stream_type) do
    {:via, Registry, {BinanceRegistry, {:ws, symbol, stream_type}}}
  end

  # Handle incoming messages
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} ->
        process_event(event, state)
        {:ok, state}
      
      {:error, reason} ->
        Logger.error("Failed to decode message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  # Handle ping/pong
  def handle_ping({:ping, msg}, state) do
    Logger.debug("Received ping, sending pong")
    {:reply, {:pong, msg}, state}
  end

  # Handle disconnections
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warn("WebSocket disconnected: #{inspect(reason)}")
    
    # Exponential backoff
    backoff = calculate_backoff(state.retry_count)
    Process.sleep(backoff)
    
    {:reconnect, %{state | retry_count: state.retry_count + 1}}
  end

  defp process_event(%{"e" => "trade"} = event, state) do
    trade = %{
      symbol: event["s"],
      price: event["p"],
      quantity: event["q"],
      time: event["T"],
      buyer_is_maker: event["m"]
    }
    
    # Broadcast to subscribers
    Phoenix.PubSub.broadcast(
      MyApp.PubSub,
      "market:#{state.symbol}",
      {:trade, trade}
    )
  end

  defp process_event(%{"e" => "kline"} = event, state) do
    kline = event["k"]
    
    candle = %{
      symbol: kline["s"],
      interval: kline["i"],
      open: kline["o"],
      high: kline["h"],
      low: kline["l"],
      close: kline["c"],
      volume: kline["v"],
      closed: kline["x"]
    }
    
    Phoenix.PubSub.broadcast(
      MyApp.PubSub,
      "market:#{state.symbol}:kline",
      {:kline, candle}
    )
  end

  defp calculate_backoff(retry_count) do
    # Exponential backoff: 5s, 10s, 20s, 40s, max 60s
    min(5_000 * :math.pow(2, retry_count), 60_000) |> trunc()
  end
end
```

### WebSocket Supervision

```elixir
defmodule BinanceStreamSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_stream(symbol, stream_type) do
    spec = {BinanceWebSocket, {symbol, stream_type}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_stream(symbol, stream_type) do
    case Registry.lookup(BinanceRegistry, {:ws, symbol, stream_type}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
```

### Reconnection Strategies

**Best practices for WebSocket reliability:**

1. **Exponential backoff**: 5s → 10s → 20s → 40s → 60s (max)
2. **Max retry attempts**: 5 before escalating to supervisor
3. **Ping/Pong health checks**: Server pings every 20 seconds
4. **24-hour timeout**: Binance disconnects after 24 hours, require reconnect
5. **State recovery**: Re-subscribe to streams after reconnection

```elixir
defmodule BinanceReconnectionHandler do
  use GenServer

  def handle_info({:ws_disconnected, pid, reason}, state) do
    Logger.warn("WebSocket disconnected: #{inspect(reason)}")
    
    cond do
      state.retry_count >= 5 ->
        # Escalate to supervisor
        Logger.error("Max retries exceeded, restarting supervisor")
        {:stop, :max_retries, state}
      
      reason == :normal ->
        # Clean disconnect, don't retry
        {:noreply, state}
      
      true ->
        # Schedule reconnection
        backoff = calculate_backoff(state.retry_count)
        Process.send_after(self(), :reconnect, backoff)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end

  def handle_info(:reconnect, state) do
    case BinanceWebSocket.start_link(state.symbol, state.stream_type) do
      {:ok, pid} ->
        Logger.info("Successfully reconnected WebSocket")
        {:noreply, %{state | pid: pid, retry_count: 0}}
      
      {:error, reason} ->
        Logger.error("Reconnection failed: #{inspect(reason)}")
        backoff = calculate_backoff(state.retry_count)
        Process.send_after(self(), :reconnect, backoff)
        {:noreply, %{state | retry_count: state.retry_count + 1}}
    end
  end
end
```

## Common REST API Operations

### Getting Market Data

```elixir
# Get current price
Binance.Market.get_ticker_price("BTCUSDT")
# => {:ok, %{symbol: "BTCUSDT", price: "45000.00"}}

# Get 24h ticker statistics
Binance.Market.get_24h_ticker("BTCUSDT")
# => {:ok, %{priceChange: "1500.00", priceChangePercent: "3.45", ...}}

# Get order book depth
Binance.Market.get_depth("BTCUSDT", 100)
# => {:ok, %{bids: [...], asks: [...]}}

# Get recent trades
Binance.Market.get_trades("BTCUSDT", 500)
```

### Placing Orders

```elixir
# Market buy order
Binance.Trade.post_order("BTCUSDT", "BUY", "MARKET", quantity: 0.001)

# Limit sell order
Binance.Trade.post_order("BTCUSDT", "SELL", "LIMIT", 
  quantity: 0.001,
  price: "46000.00",
  time_in_force: "GTC"  # Good Till Cancel
)

# Stop-loss order
Binance.Trade.post_order("BTCUSDT", "SELL", "STOP_LOSS_LIMIT",
  quantity: 0.001,
  price: "44000.00",
  stop_price: "44500.00",
  time_in_force: "GTC"
)
```

### Checking Account Information

```elixir
# Get account info (balances, permissions)
{:ok, account} = Binance.Account.get_account()

# Available balance
btc_balance = Enum.find(account.balances, &(&1.asset == "BTC"))
available = Decimal.new(btc_balance.free)
locked = Decimal.new(btc_balance.locked)

# Get open orders
{:ok, orders} = Binance.Trade.get_open_orders("BTCUSDT")

# Get order history
{:ok, history} = Binance.Trade.get_all_orders("BTCUSDT", limit: 100)
```

## Error Handling

### Common Error Codes

| Code | Message | Action |
|------|---------|--------|
| -1000 | Unknown error | Retry with backoff |
| -1003 | Too many requests | Wait and reduce frequency |
| -1021 | Timestamp out of sync | Sync system time |
| -1022 | Invalid signature | Check API secret |
| -2010 | Insufficient balance | Check account balance |
| -2011 | Unknown order | Order doesn't exist |

### Error Handler Implementation

```elixir
defmodule BinanceErrorHandler do
  require Logger

  def handle_error({:error, %{"code" => -1021, "msg" => msg}}) do
    Logger.error("Timestamp sync error: #{msg}")
    # Sync system time
    sync_time()
    {:error, :timestamp_sync_required}
  end

  def handle_error({:error, %{"code" => -2010, "msg" => msg}}) do
    Logger.error("Insufficient balance: #{msg}")
    {:error, :insufficient_balance}
  end

  def handle_error({:error, %{"code" => -1003}}) do
    Logger.warn("Rate limit hit, backing off")
    Process.sleep(60_000)  # Wait 1 minute
    {:error, :rate_limited}
  end

  def handle_error({:error, reason}) do
    Logger.error("Binance API error: #{inspect(reason)}")
    {:error, reason}
  end

  defp sync_time do
    # Get server time and adjust local clock
    case Binance.Market.get_server_time() do
      {:ok, %{server_time: server_time}} ->
        local_time = System.system_time(:millisecond)
        diff = server_time - local_time
        Logger.info("Time diff: #{diff}ms")
      _ ->
        :error
    end
  end
end
```

## Testing Strategies

### Using Binance Testnet

```elixir
# config/test.exs
config :binance,
  api_key: System.get_env("BINANCE_TESTNET_KEY"),
  api_secret: System.get_env("BINANCE_TESTNET_SECRET"),
  end_point: "https://testnet.binance.vision"
```

### Mocking API Responses

```elixir
# Use Mox for testing
defmodule BinanceClientMock do
  use GenServer

  def get_ticker_price(symbol) do
    {:ok, %{symbol: symbol, price: "45000.00"}}
  end

  def post_order(symbol, side, type, opts) do
    {:ok, %{
      symbol: symbol,
      order_id: 12345,
      status: "FILLED",
      side: side,
      type: type
    }}
  end
end
```

## Best Practices

1. **Always use rate limiter** before making requests
2. **Implement circuit breakers** for API failures
3. **Log all trading operations** for audit trail
4. **Use testnet first** before production
5. **Monitor WebSocket health** with ping/pong
6. **Handle time synchronization** (use NTP)
7. **Secure API credentials** with encryption
8. **Implement retry logic** with exponential backoff
9. **Track response headers** for rate limit monitoring
10. **Use Registry** for WebSocket process management

## Additional Resources

For detailed examples and advanced patterns:
- `references/api_endpoints.md` - Complete endpoint documentation
- `references/error_codes.md` - All Binance error codes and solutions
- `scripts/test_connection.py` - Script to test Binance connectivity
