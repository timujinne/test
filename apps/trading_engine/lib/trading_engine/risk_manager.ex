defmodule TradingEngine.RiskManager do
  @moduledoc """
  Risk management module to validate orders before execution.
  """
  require Logger

  alias SharedData.Types

  @max_position_size Decimal.new("1.0")  # 1 BTC
  @max_order_size Decimal.new("0.1")     # 0.1 BTC
  @max_daily_loss Decimal.new("1000")    # $1000 USDT

  @spec check_order(Types.order_params(), map()) :: :ok | {:error, String.t()}
  def check_order(order_params, state) do
    with :ok <- check_order_size(order_params),
         :ok <- check_position_size(order_params, state),
         :ok <- check_daily_loss(state) do
      :ok
    end
  end

  @spec check_order_size(Types.order_params()) :: :ok | {:error, String.t()}
  defp check_order_size(%{quantity: quantity}) do
    qty = Decimal.new(quantity)

    if Decimal.compare(qty, @max_order_size) == :gt do
      {:error, "Order size exceeds maximum allowed (#{@max_order_size})"}
    else
      :ok
    end
  end

  defp check_order_size(_), do: :ok

  @spec check_position_size(Types.order_params(), map()) :: :ok | {:error, String.t()}
  defp check_position_size(%{side: "BUY", quantity: quantity}, state) do
    current_position_size = calculate_position_size(state.positions)
    new_qty = Decimal.new(quantity)
    total_size = Decimal.add(current_position_size, new_qty)

    if Decimal.compare(total_size, @max_position_size) == :gt do
      {:error, "Position size would exceed maximum allowed (#{@max_position_size})"}
    else
      :ok
    end
  end

  defp check_position_size(_, _), do: :ok

  @spec check_daily_loss(map()) :: :ok | {:error, String.t()}
  defp check_daily_loss(_state) do
    # This would need to query database for today's trades
    # For now, simplified implementation
    # TODO: Implement actual daily loss check using @max_daily_loss
    :ok
  end

  @spec calculate_position_size(map()) :: Decimal.t()
  defp calculate_position_size(positions) do
    Enum.reduce(positions, Decimal.new(0), fn {_symbol, pos}, acc ->
      Decimal.add(acc, pos.quantity || Decimal.new(0))
    end)
  end
end
