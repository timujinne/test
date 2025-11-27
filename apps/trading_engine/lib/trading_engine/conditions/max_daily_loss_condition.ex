defmodule TradingEngine.Conditions.MaxDailyLossCondition do
  @moduledoc """
  Max daily loss condition for automatically stopping all strategies
  on an account when total daily loss exceeds the limit.

  Config:
  - limit: Maximum daily loss in USDT (e.g., 500)
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    limit = Condition.parse_number(config["limit"])

    if is_number(limit) and limit > 0 do
      {:ok, %{
        limit: Decimal.negate(Decimal.new("#{limit}")),
        last_reset_date: Date.utc_today()
      }}
    else
      {:error, :invalid_limit}
    end
  end

  @impl true
  def evaluate(market_data, state) do
    # Check if we need to reset for a new day
    today = Date.utc_today()
    state =
      if Date.compare(today, state.last_reset_date) != :eq do
        %{state | last_reset_date: today}
      else
        state
      end

    # market_data should contain daily_pnl for the account
    daily_pnl = market_data["daily_pnl"] || market_data[:daily_pnl]

    met? =
      if is_number(daily_pnl) do
        # Stop if daily_pnl is less than or equal to limit (both negative)
        Decimal.compare(Decimal.new("#{daily_pnl}"), state.limit) != :gt
      else
        false
      end

    {met?, state}
  end

  @impl true
  def type, do: :stop

  @impl true
  def describe(state) do
    display_limit = Decimal.abs(state.limit)
    "Max daily loss #{Decimal.to_string(display_limit)} USDT"
  end
end
