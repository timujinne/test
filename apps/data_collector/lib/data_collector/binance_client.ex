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
        filtered = Enum.filter(balances, fn b -> 
          Decimal.compare(Decimal.new(b["free"]), 0) == :gt or
          Decimal.compare(Decimal.new(b["locked"]), 0) == :gt
        end)
        {:ok, filtered}
        
      error -> error
    end
  end

  @doc """
  Create a new order.
  """
  @spec create_order(Types.api_key(), Types.secret_key(), Types.order_params()) :: Types.result(Types.order())
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
  @spec cancel_order(Types.api_key(), Types.secret_key(), Types.symbol(), Types.order_id()) :: Types.result(map())
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
end
