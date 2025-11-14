defmodule SharedData.Config do
  @moduledoc """
  Centralized configuration for timeouts, limits, and other constants
  used across the Binance Trading System.

  ## Timeouts

  Different operations have different timeout requirements:

  - **Fast operations** (1s): Simple reads from GenServer state, ETS lookups
  - **Normal operations** (5s): Default GenServer operations
  - **API operations** (30s): External API calls that may be slow
  - **Long operations** (60s): Complex calculations, database queries

  ## Usage

      # In a GenServer call
      GenServer.call(pid, :get_state, Config.timeout(:fast))

      # For API calls
      GenServer.call(pid, {:place_order, params}, Config.timeout(:api))
  """

  # GenServer call timeouts (in milliseconds)
  @timeout_fast 1_000       # 1 second - for simple reads
  @timeout_normal 5_000     # 5 seconds - default operations
  @timeout_api 30_000       # 30 seconds - external API calls
  @timeout_long 60_000      # 60 seconds - complex operations

  # Rate limiting
  @rate_limit_binance_weight 1200     # Binance API weight per minute
  @rate_limit_binance_orders 100      # Binance order limit per 10 seconds
  @rate_limit_window_ms 60_000        # 1 minute window

  # WebSocket reconnection
  @ws_initial_backoff 1_000           # 1 second
  @ws_max_backoff 300_000             # 5 minutes
  @ws_backoff_multiplier 2
  @ws_max_reconnect_attempts 10

  # Circuit breaker
  @circuit_breaker_threshold 10        # failures before opening
  @circuit_breaker_window_ms 10_000   # 10 seconds
  @circuit_breaker_reset_ms 60_000    # 1 minute

  # Risk management
  @max_daily_loss_usd 1000
  @max_position_size_btc 1.0
  @max_order_size_btc 0.1

  @doc """
  Returns the timeout value for the given operation type.

  ## Types

  - `:fast` - 1 second - for simple reads (state, ETS)
  - `:normal` - 5 seconds - default operations
  - `:api` - 30 seconds - external API calls
  - `:long` - 60 seconds - complex operations

  ## Examples

      iex> Config.timeout(:fast)
      1000

      iex> Config.timeout(:api)
      30000
  """
  def timeout(:fast), do: @timeout_fast
  def timeout(:normal), do: @timeout_normal
  def timeout(:api), do: @timeout_api
  def timeout(:long), do: @timeout_long
  def timeout(_), do: @timeout_normal

  @doc """
  Returns rate limiting configuration.
  """
  def rate_limit(:binance_weight), do: @rate_limit_binance_weight
  def rate_limit(:binance_orders), do: @rate_limit_binance_orders
  def rate_limit(:window_ms), do: @rate_limit_window_ms

  @doc """
  Returns WebSocket reconnection configuration.
  """
  def websocket(:initial_backoff), do: @ws_initial_backoff
  def websocket(:max_backoff), do: @ws_max_backoff
  def websocket(:backoff_multiplier), do: @ws_backoff_multiplier
  def websocket(:max_reconnect_attempts), do: @ws_max_reconnect_attempts

  @doc """
  Returns circuit breaker configuration.
  """
  def circuit_breaker(:threshold), do: @circuit_breaker_threshold
  def circuit_breaker(:window_ms), do: @circuit_breaker_window_ms
  def circuit_breaker(:reset_ms), do: @circuit_breaker_reset_ms

  @doc """
  Returns risk management limits.
  """
  def risk_limit(:max_daily_loss_usd), do: @max_daily_loss_usd
  def risk_limit(:max_position_size_btc), do: @max_position_size_btc
  def risk_limit(:max_order_size_btc), do: @max_order_size_btc
end
