defmodule DataCollector.BinanceClient do
  @moduledoc """
  HTTP client for Binance REST API with rate limiting and signature generation.
  """
  require Logger

  alias SharedData.Types

  @base_url Application.compile_env(:binance, :end_point, "https://api.binance.com")

  @doc """
  Get account information including balances.
  """
  @spec get_account(Types.api_key(), Types.secret_key()) :: Types.result(map())
  def get_account(api_key, secret_key) do
    params = %{timestamp: timestamp(), recvWindow: 5000}
    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(10) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/account",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_account(api_key, secret_key)
    end
  end

  @doc """
  Get account balances.
  """
  @spec get_balances(Types.api_key(), Types.secret_key()) :: Types.result([map()])
  def get_balances(api_key, secret_key) do
    case get_account(api_key, secret_key) do
      {:ok, %{"balances" => balances}} ->
        filtered =
          Enum.filter(balances, fn b ->
            Decimal.compare(Decimal.new(b["free"]), 0) == :gt or
              Decimal.compare(Decimal.new(b["locked"]), 0) == :gt
          end)

        {:ok, filtered}

      error ->
        error
    end
  end

  @doc """
  Create a new order.
  """
  @spec create_order(Types.api_key(), Types.secret_key(), Types.order_params()) ::
          Types.result(Types.order())
  def create_order(api_key, secret_key, params) do
    timestamp = timestamp()
    order_params = Map.merge(params, %{timestamp: timestamp, recvWindow: 5000})
    signature = generate_signature(order_params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.post(
               "#{@base_url}/api/v3/order",
               URI.encode_query(Map.put(order_params, :signature, signature)),
               headers
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        create_order(api_key, secret_key, params)
    end
  end

  @doc """
  Cancel an order.
  """
  @spec cancel_order(Types.api_key(), Types.secret_key(), Types.symbol(), Types.order_id()) ::
          Types.result(map())
  def cancel_order(api_key, secret_key, symbol, order_id) do
    params = %{
      symbol: symbol,
      orderId: order_id,
      timestamp: timestamp(),
      recvWindow: 5000
    }

    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.delete(
               "#{@base_url}/api/v3/order",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        cancel_order(api_key, secret_key, symbol, order_id)
    end
  end

  @doc """
  Cancel all open orders for a symbol.
  """
  @spec cancel_all_orders(Types.api_key(), Types.secret_key(), Types.symbol()) ::
          Types.result([map()])
  def cancel_all_orders(api_key, secret_key, symbol) do
    params = %{
      symbol: symbol,
      timestamp: timestamp(),
      recvWindow: 5000
    }

    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.delete(
               "#{@base_url}/api/v3/openOrders",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        cancel_all_orders(api_key, secret_key, symbol)
    end
  end

  @doc """
  Get exchange info with all trading pairs.
  Returns list of symbols with their status and filters.
  """
  @spec get_exchange_info() :: Types.result(map())
  def get_exchange_info do
    with :ok <- DataCollector.RateLimiter.check_limit(10) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get("#{@base_url}/api/v3/exchangeInfo") do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Process.sleep(ms)
        get_exchange_info()
    end
  end

  @doc """
  Get all ticker prices.
  """
  @spec get_all_ticker_prices() :: Types.result([map()])
  def get_all_ticker_prices do
    with :ok <- DataCollector.RateLimiter.check_limit(2) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get("#{@base_url}/api/v3/ticker/price") do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Process.sleep(ms)
        get_all_ticker_prices()
    end
  end

  @doc """
  Get current price for a symbol.
  """
  @spec get_ticker_price(Types.symbol()) :: Types.result(map())
  def get_ticker_price(symbol) do
    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get("#{@base_url}/api/v3/ticker/price", [], params: %{symbol: symbol}) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Process.sleep(ms)
        get_ticker_price(symbol)
    end
  end

  @doc """
  Get order book (depth) for a symbol.
  Returns bids and asks up to specified limit.

  ## Parameters
  - symbol: Trading pair symbol (e.g., "BTCUSDT")
  - limit: Order book depth (5, 10, 20, 50, 100, 500, 1000), defaults to 100

  ## Response
  Returns a map with:
  - "lastUpdateId": Update ID
  - "bids": List of [price, quantity] pairs
  - "asks": List of [price, quantity] pairs
  """
  @spec get_depth(Types.symbol(), pos_integer()) :: Types.result(map())
  def get_depth(symbol, limit \\ 100) do
    with :ok <- DataCollector.RateLimiter.check_limit(5) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/depth",
               [],
               params: %{symbol: symbol, limit: limit}
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_depth(symbol, limit)
    end
  end

  @doc """
  Get kline/candlestick data for a symbol.

  ## Parameters
  - symbol: Trading pair symbol (e.g., "BTCUSDT")
  - interval: Kline interval (1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 8h, 12h, 1d, 3d, 1w, 1M)
  - opts: Optional parameters
    - :limit - Number of klines to return (default 500, max 1000)
    - :startTime - Start time in milliseconds
    - :endTime - End time in milliseconds

  ## Response
  Returns a list of kline arrays, each containing:
  [openTime, open, high, low, close, volume, closeTime, quoteAssetVolume,
   numberOfTrades, takerBuyBaseAssetVolume, takerBuyQuoteAssetVolume, ignore]
  """
  @spec get_klines(Types.symbol(), String.t(), keyword()) :: Types.result([list()])
  def get_klines(symbol, interval, opts \\ []) do
    params =
      %{symbol: symbol, interval: interval}
      |> maybe_put(:limit, opts[:limit])
      |> maybe_put(:startTime, opts[:startTime])
      |> maybe_put(:endTime, opts[:endTime])

    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/klines",
               [],
               params: params
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_klines(symbol, interval, opts)
    end
  end

  @doc """
  Get 24 hour rolling window price change statistics.

  ## Parameters
  - symbol: Trading pair symbol (e.g., "BTCUSDT")

  ## Response
  Returns a map with 24h statistics including:
  - "priceChange": Absolute price change
  - "priceChangePercent": Price change percentage
  - "highPrice": Highest price in 24h
  - "lowPrice": Lowest price in 24h
  - "volume": Trading volume
  - "lastPrice": Last traded price
  - And more...
  """
  @spec get_24h_ticker(Types.symbol()) :: Types.result(map())
  def get_24h_ticker(symbol) do
    with :ok <- DataCollector.RateLimiter.check_limit(1) do
      # Wrap HTTP call in circuit breaker
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/ticker/24hr",
               [],
               params: %{symbol: symbol}
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_24h_ticker(symbol)
    end
  end

  @doc """
  Get all open orders for an account or a specific symbol.

  ## Parameters
  - api_key: Binance API key
  - secret_key: Binance secret key
  - symbol: (Optional) Trading pair symbol (e.g., "BTCUSDT"). If omitted, returns all open orders.

  ## Response
  Returns a list of open order maps with order details including:
  - "orderId": Order ID
  - "symbol": Trading pair
  - "side": BUY or SELL
  - "type": Order type (LIMIT, MARKET, etc.)
  - "price": Order price
  - "origQty": Original quantity
  - "executedQty": Executed quantity
  - "status": Order status (should be NEW or PARTIALLY_FILLED)
  - "time": Order creation time
  - "updateTime": Last update time
  """
  @spec get_open_orders(Types.api_key(), Types.secret_key(), Types.symbol() | nil) ::
          Types.result([map()])
  def get_open_orders(api_key, secret_key, symbol \\ nil) do
    params =
      %{
        timestamp: timestamp(),
        recvWindow: 5000
      }
      |> maybe_put(:symbol, symbol)

    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(3) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/openOrders",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_open_orders(api_key, secret_key, symbol)
    end
  end

  @doc """
  Get all orders for a symbol (active, canceled, or filled).

  ## Parameters
  - api_key: Binance API key
  - secret_key: Binance secret key
  - symbol: Trading pair symbol (e.g., "BTCUSDT")
  - opts: Optional parameters
    - :orderId - Order ID to get orders from (inclusive)
    - :startTime - Start time in milliseconds
    - :endTime - End time in milliseconds
    - :limit - Number of orders to return (default 500, max 1000)

  ## Response
  Returns a list of order maps with order details including:
  - "orderId": Order ID
  - "symbol": Trading pair
  - "side": BUY or SELL
  - "type": Order type (LIMIT, MARKET, etc.)
  - "price": Order price
  - "origQty": Original quantity
  - "executedQty": Executed quantity
  - "status": Order status (NEW, FILLED, CANCELED, etc.)
  - "time": Order creation time
  - "updateTime": Last update time
  """
  @spec get_all_orders(Types.api_key(), Types.secret_key(), Types.symbol(), keyword()) ::
          Types.result([map()])
  def get_all_orders(api_key, secret_key, symbol, opts \\ []) do
    params =
      %{
        symbol: symbol,
        timestamp: timestamp(),
        recvWindow: 5000
      }
      |> maybe_put(:orderId, opts[:orderId])
      |> maybe_put(:startTime, opts[:startTime])
      |> maybe_put(:endTime, opts[:endTime])
      |> maybe_put(:limit, opts[:limit])

    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(10) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/allOrders",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_all_orders(api_key, secret_key, symbol, opts)
    end
  end

  @doc """
  Get all trades for a symbol.

  ## Parameters
  - api_key: Binance API key
  - secret_key: Binance secret key
  - symbol: Trading pair symbol (e.g., "BTCUSDT")
  - opts: Optional parameters
    - :orderId - Order ID to get trades from
    - :startTime - Start time in milliseconds
    - :endTime - End time in milliseconds
    - :fromId - Trade ID to fetch from (inclusive)
    - :limit - Number of trades to return (default 500, max 1000)

  ## Response
  Returns a list of trade maps with trade details including:
  - "id": Trade ID
  - "orderId": Order ID
  - "symbol": Trading pair
  - "side": BUY or SELL (derived from isBuyer)
  - "price": Trade price
  - "qty": Trade quantity
  - "quoteQty": Quote asset quantity
  - "commission": Commission paid
  - "commissionAsset": Asset in which commission was paid
  - "time": Trade execution time
  - "isBuyer": Whether buyer
  - "isMaker": Whether maker
  """
  @spec get_my_trades(Types.api_key(), Types.secret_key(), Types.symbol(), keyword()) ::
          Types.result([map()])
  def get_my_trades(api_key, secret_key, symbol, opts \\ []) do
    params =
      %{
        symbol: symbol,
        timestamp: timestamp(),
        recvWindow: 5000
      }
      |> maybe_put(:orderId, opts[:orderId])
      |> maybe_put(:startTime, opts[:startTime])
      |> maybe_put(:endTime, opts[:endTime])
      |> maybe_put(:fromId, opts[:fromId])
      |> maybe_put(:limit, opts[:limit])

    signature = generate_signature(params, secret_key)

    headers = [
      {"X-MBX-APIKEY", api_key}
    ]

    with :ok <- DataCollector.RateLimiter.check_limit(10) do
      DataCollector.CircuitBreaker.call(:binance_api, fn ->
        case HTTPoison.get(
               "#{@base_url}/api/v3/myTrades",
               headers,
               params: Map.put(params, :signature, signature)
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %{status_code: status, body: body}} ->
            {:error, "HTTP #{status}: #{body}"}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    else
      {:wait, ms} ->
        Logger.warning("Rate limit reached, waiting #{ms}ms")
        Process.sleep(ms)
        get_my_trades(api_key, secret_key, symbol, opts)
    end
  end

  # Private functions

  @spec timestamp() :: Types.timestamp()
  defp timestamp do
    System.system_time(:millisecond)
  end

  @spec generate_signature(map(), Types.secret_key()) :: String.t()
  defp generate_signature(params, secret_key) do
    query_string = URI.encode_query(params)

    :crypto.mac(:hmac, :sha256, secret_key, query_string)
    |> Base.encode16(case: :lower)
  end

  @spec maybe_put(map(), atom(), any()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
