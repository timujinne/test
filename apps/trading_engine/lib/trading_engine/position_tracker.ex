defmodule TradingEngine.PositionTracker do
  @moduledoc """
  Tracks open positions and calculates P&L.
  """
  require Logger

  def calculate_pnl(positions, current_price) do
    Enum.reduce(positions, Decimal.new(0), fn position, acc ->
      entry_price = position.entry_price
      quantity = position.quantity

      pnl = Decimal.mult(
        quantity,
        Decimal.sub(current_price, entry_price)
      )

      Decimal.add(acc, pnl)
    end)
  end

  def average_entry_price(positions) do
    total_cost = Enum.reduce(positions, Decimal.new(0), fn p, acc ->
      cost = Decimal.mult(p.entry_price, p.quantity)
      Decimal.add(acc, cost)
    end)

    total_quantity = Enum.reduce(positions, Decimal.new(0), fn p, acc ->
      Decimal.add(acc, p.quantity)
    end)

    if Decimal.compare(total_quantity, 0) == :gt do
      Decimal.div(total_cost, total_quantity)
    else
      Decimal.new(0)
    end
  end

  def update_positions(positions, execution) do
    side = execution["S"]
    price = Decimal.new(execution["L"])
    qty = Decimal.new(execution["l"])

    case side do
      "BUY" ->
        [%{entry_price: price, quantity: qty, timestamp: System.system_time(:millisecond)} | positions]

      "SELL" ->
        # Remove quantity from positions (FIFO)
        reduce_positions(positions, qty)
    end
  end

  defp reduce_positions(positions, qty_to_reduce) do
    reduce_positions(positions, qty_to_reduce, [])
  end

  defp reduce_positions([], _qty, acc), do: Enum.reverse(acc)

  defp reduce_positions([position | rest], qty_to_reduce, acc) do
    cond do
      Decimal.compare(qty_to_reduce, 0) == :eq ->
        Enum.reverse(acc) ++ [position | rest]

      Decimal.compare(position.quantity, qty_to_reduce) == :gt ->
        new_position = %{position | quantity: Decimal.sub(position.quantity, qty_to_reduce)}
        Enum.reverse([new_position | acc]) ++ rest

      Decimal.compare(position.quantity, qty_to_reduce) == :eq ->
        Enum.reverse(acc) ++ rest

      true ->
        reduce_positions(rest, Decimal.sub(qty_to_reduce, position.quantity), acc)
    end
  end
end
