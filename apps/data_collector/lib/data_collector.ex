defmodule DataCollector do
  @moduledoc """
  DataCollector collects market data and account information from Binance.

  This module serves as the main API for interacting with Binance.
  """

  @doc """
  Get current market price for a symbol.
  """
  defdelegate get_price(symbol), to: DataCollector.MarketData

  @doc """
  Subscribe to market data updates.
  """
  defdelegate subscribe, to: DataCollector.MarketData

  @doc """
  Get account information.
  """
  defdelegate get_account_info(api_key, secret_key), to: DataCollector.BinanceClient

  @doc """
  Get account balances.
  """
  defdelegate get_balances(api_key, secret_key), to: DataCollector.BinanceClient

  @doc """
  Place a new order.
  """
  defdelegate place_order(api_key, secret_key, order_params), to: DataCollector.BinanceClient

  @doc """
  Get order status.
  """
  defdelegate get_order(api_key, secret_key, symbol, order_id), to: DataCollector.BinanceClient

  @doc """
  Cancel an order.
  """
  defdelegate cancel_order(api_key, secret_key, symbol, order_id), to: DataCollector.BinanceClient
end
