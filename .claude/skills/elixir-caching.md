---
name: elixir-caching
description: Multi-tier caching strategies with ETS, Redis, and Nebulex for Elixir applications. Use when implementing performance optimizations, reducing database load, or building distributed caching layers.
---

# Elixir Caching Strategies

## Nebulex Setup

```elixir
# mix.exs
{:nebulex, "~> 3.0"},
{:nebulex_redis_adapter, "~> 3.0"}

# L1 Cache - ETS (local)
defmodule MyApp.Cache.L1 do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local
end

# L2 Cache - Redis (distributed)
defmodule MyApp.Cache.L2 do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: NebulexRedisAdapter
end

# config/config.exs
config :my_app, MyApp.Cache.L2,
  conn_opts: [
    host: "localhost",
    port: 6379
  ]
```

## Multi-Tier Cache

```elixir
defmodule MyApp.Cache do
  alias MyApp.Cache.{L1, L2}

  def get(key) do
    case L1.get(key) do
      nil ->
        case L2.get(key) do
          nil -> nil
          value ->
            L1.put(key, value)
            value
        end
      value -> value
    end
  end

  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :timer.minutes(5))
    L2.put(key, value, ttl: ttl)
    L1.put(key, value, ttl: ttl)
  end

  def delete(key) do
    L1.delete(key)
    L2.delete(key)
  end
end
```

## Declarative Caching

```elixir
defmodule MyApp.Prices do
  use Nebulex.Caching

  @decorate cacheable(cache: MyApp.Cache.L1, key: {symbol}, opts: [ttl: 60_000])
  def get_price(symbol) do
    BinanceAPI.get_ticker_price(symbol)
  end

  @decorate cache_evict(cache: MyApp.Cache.L1, key: {symbol})
  def invalidate_price(symbol) do
    :ok
  end
end
```

## ETS Tables

```elixir
# Create table
:ets.new(:my_cache, [:set, :public, :named_table])

# Insert
:ets.insert(:my_cache, {"key", "value"})

# Lookup
case :ets.lookup(:my_cache, "key") do
  [{"key", value}] -> {:ok, value}
  [] -> {:error, :not_found}
end

# Delete
:ets.delete(:my_cache, "key")
```

## Cache Strategies

1. **Price data**: L1 30-60s TTL, L2 5min TTL
2. **User sessions**: Redis 24h TTL
3. **Balance data**: L1 30s TTL, invalidate on transaction
4. **Historical data**: TimescaleDB continuous aggregates
