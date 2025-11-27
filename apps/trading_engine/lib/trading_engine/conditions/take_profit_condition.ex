defmodule TradingEngine.Conditions.TakeProfitCondition do
  @moduledoc """
  Take-profit condition for automatically stopping a strategy when profit target is reached.

  Config:
  - target_percent: Percentage profit to trigger stop (e.g., 5.0 for 5%)
  - target_amount: Absolute profit amount in USDT (alternative to percent)
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    target_percent = Condition.parse_number(config["target_percent"])
    target_amount = Condition.parse_number(config["target_amount"])

    cond do
      is_number(target_percent) and target_percent > 0 ->
        {:ok, %{type: :percent, target: Decimal.new("#{target_percent}")}}

      is_number(target_amount) and target_amount > 0 ->
        {:ok, %{type: :amount, target: Decimal.new("#{target_amount}")}}

      true ->
        {:error, :invalid_target}
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
          Decimal.compare(Decimal.new("#{pnl_percent}"), state.target) != :lt

        :amount when is_number(pnl) ->
          Decimal.compare(Decimal.new("#{pnl}"), state.target) != :lt

        _ ->
          false
      end

    {met?, state}
  end

  @impl true
  def type, do: :stop

  @impl true
  def describe(state) do
    case state.type do
      :percent -> "Take profit at #{Decimal.to_string(state.target)}%"
      :amount -> "Take profit at #{Decimal.to_string(state.target)} USDT"
    end
  end
end
