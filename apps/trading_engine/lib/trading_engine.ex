defmodule TradingEngine do
  @moduledoc """
  TradingEngine manages trading strategies and order execution.

  Main API for starting/stopping traders and managing trading operations.
  """

  @doc """
  Start trading for a user.
  """
  defdelegate start_trading(user_id, api_key, secret_key, strategy \\ :naive), to: TradingEngine.Trader

  @doc """
  Stop trading for a user.
  """
  defdelegate stop_trading(user_id), to: TradingEngine.Trader

  @doc """
  Get current trader state.
  """
  defdelegate get_state(user_id), to: TradingEngine.Trader

  @doc """
  Place an order.
  """
  defdelegate place_order(user_id, api_key, secret_key, order_params), to: TradingEngine.OrderManager

  @doc """
  Cancel an order.
  """
  defdelegate cancel_order(user_id, api_key, secret_key, symbol, order_id), to: TradingEngine.OrderManager

  @doc """
  Calculate position size.
  """
  defdelegate calculate_position_size(user_id, symbol, price, account_balance), to: TradingEngine.RiskManager

  @doc """
  Check if trade is allowed.
  """
  defdelegate check_trade_allowed(user_id, symbol, side, quantity, price), to: TradingEngine.RiskManager

  @doc """
  Calculate stop-loss price.
  """
  defdelegate calculate_stop_loss(side, entry_price, stop_loss_percent \\ nil), to: TradingEngine.RiskManager
end
