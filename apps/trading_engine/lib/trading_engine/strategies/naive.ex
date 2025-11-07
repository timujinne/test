defmodule TradingEngine.Strategies.Naive do
  @moduledoc """
  Naive trading strategy: Buy low, sell high.

  This is a simple strategy that:
  1. Monitors price movements
  2. Buys when price drops by a certain percentage
  3. Sells when price increases by a certain percentage

  This is meant as an example and should NOT be used in production without proper testing.
  """

  require Logger

  @buy_threshold_percent -2.0
  @sell_threshold_percent 3.0

  @doc """
  Evaluate the naive strategy based on current price and position.

  Returns {:buy, quantity}, {:sell, quantity}, or :hold
  """
  def evaluate(symbol, current_price, last_price, position, balance) do
    price_change_percent = calculate_price_change_percent(current_price, last_price)

    cond do
      # Price dropped, consider buying
      price_change_percent <= @buy_threshold_percent and has_balance?(balance) ->
        quantity = calculate_buy_quantity(current_price, balance)
        Logger.info("[Naive] Buy signal for #{symbol}: price changed by #{price_change_percent}%")
        {:buy, quantity}

      # Price increased, consider selling
      price_change_percent >= @sell_threshold_percent and has_position?(position) ->
        quantity = get_position_quantity(position)
        Logger.info("[Naive] Sell signal for #{symbol}: price changed by #{price_change_percent}%")
        {:sell, quantity}

      # Hold current position
      true ->
        :hold
    end
  end

  defp calculate_price_change_percent(current, last) when is_number(current) and is_number(last) do
    (current - last) / last * 100
  end

  defp calculate_price_change_percent(_current, _last), do: 0.0

  defp has_balance?(balance) when is_map(balance) do
    usdt = Map.get(balance, "USDT", 0)
    # Minimum balance to trade
    usdt > 10.0
  end

  defp has_balance?(_), do: false

  defp has_position?(position) when is_map(position) do
    quantity = Map.get(position, :quantity, 0)
    quantity > 0
  end

  defp has_position?(_), do: false

  defp get_position_quantity(position) when is_map(position) do
    Map.get(position, :quantity, 0)
  end

  defp get_position_quantity(_), do: 0

  defp calculate_buy_quantity(price, balance) when is_number(price) and is_map(balance) do
    usdt = Map.get(balance, "USDT", 0)
    # Use 50% of available balance
    usdt * 0.5 / price
  end

  defp calculate_buy_quantity(_price, _balance), do: 0
end
