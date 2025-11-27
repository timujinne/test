defmodule TradingEngine.Conditions.StopLossCondition do
  @moduledoc """
  Stop-loss condition for automatically stopping a strategy when loss limit is reached.

  Config:
  - limit_percent: Percentage loss to trigger stop (e.g., 2.0 for 2% loss)
  - limit_amount: Absolute loss amount in USDT (alternative to percent)
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    limit_percent = Condition.parse_number(config["limit_percent"])
    limit_amount = Condition.parse_number(config["limit_amount"])

    cond do
      is_number(limit_percent) and limit_percent > 0 ->
        # Store as negative for comparison
        {:ok, %{type: :percent, limit: Decimal.negate(Decimal.new("#{limit_percent}"))}}

      is_number(limit_amount) and limit_amount > 0 ->
        {:ok, %{type: :amount, limit: Decimal.negate(Decimal.new("#{limit_amount}"))}}

      true ->
        {:error, :invalid_limit}
    end
  end

  @impl true
  def evaluate(market_data, state) do
    # market_data should contain P&L info from the trader
    pnl = market_data["pnl"] || market_data[:pnl]
    pnl_percent = market_data["pnl_percent"] || market_data[:pnl_percent]

    met? =
      case state.type do
        :percent when is_number(pnl_percent) ->
          # Stop if pnl_percent is less than or equal to limit (both negative)
          Decimal.compare(Decimal.new("#{pnl_percent}"), state.limit) != :gt

        :amount when is_number(pnl) ->
          Decimal.compare(Decimal.new("#{pnl}"), state.limit) != :gt

        _ ->
          false
      end

    {met?, state}
  end

  @impl true
  def type, do: :stop

  @impl true
  def describe(state) do
    # Show as positive number for display
    display_limit = Decimal.abs(state.limit)

    case state.type do
      :percent -> "Stop loss at #{Decimal.to_string(display_limit)}%"
      :amount -> "Stop loss at #{Decimal.to_string(display_limit)} USDT"
    end
  end
end
