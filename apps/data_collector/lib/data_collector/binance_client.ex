defmodule DataCollector.BinanceClient do
  @moduledoc """
  HTTP client for Binance REST API with rate limiting support.
  """

  require Logger

  @base_url Application.compile_env(:binance, :end_point, "https://api.binance.com")

  @doc """
  Get account information from Binance.
  """
  def get_account_info(api_key, secret_key) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:account) do
      # TODO: Implement actual API call using binance library
      Logger.info("Getting account info for API key: #{mask_api_key(api_key)}")
      {:ok, %{}}
    end
  end

  @doc """
  Get current balances for an account.
  """
  def get_balances(api_key, secret_key) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:account) do
      Logger.info("Getting balances for API key: #{mask_api_key(api_key)}")
      {:ok, []}
    end
  end

  @doc """
  Place a new order on Binance.
  """
  def place_order(api_key, secret_key, order_params) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:order) do
      Logger.info("Placing order: #{inspect(order_params)}")
      {:ok, %{}}
    end
  end

  @doc """
  Get order status.
  """
  def get_order(api_key, secret_key, symbol, order_id) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:order) do
      Logger.info("Getting order status for #{symbol} - #{order_id}")
      {:ok, %{}}
    end
  end

  @doc """
  Cancel an order.
  """
  def cancel_order(api_key, secret_key, symbol, order_id) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:order) do
      Logger.info("Canceling order #{symbol} - #{order_id}")
      {:ok, %{}}
    end
  end

  @doc """
  Get ticker price for a symbol.
  """
  def get_ticker_price(symbol) do
    with :ok <- DataCollector.RateLimiter.check_rate_limit(:market_data) do
      Logger.debug("Getting ticker price for #{symbol}")
      {:ok, %{symbol: symbol, price: "0.00"}}
    end
  end

  # Private helper to mask API key for logging
  defp mask_api_key(api_key) when is_binary(api_key) do
    String.slice(api_key, 0..7) <> "..." <> String.slice(api_key, -4..-1)
  end
  defp mask_api_key(_), do: "***"
end
