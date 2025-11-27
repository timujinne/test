defmodule TradingEngine.Conditions.PriceCondition do
  @moduledoc """
  Price-based condition for starting/stopping strategies.

  Supports operators:
  - "above" - price is above threshold
  - "below" - price is below threshold
  - "crosses_above" - price crosses above threshold (was below, now above)
  - "crosses_below" - price crosses below threshold (was above, now below)
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    threshold = Condition.parse_number(config["value"] || config["threshold"])
    operator = config["operator"] || "below"

    if is_nil(threshold) do
      {:error, :invalid_threshold}
    else
      state = %{
        threshold: Decimal.new(threshold),
        operator: operator,
        last_price: nil,
        triggered: false
      }

      {:ok, state}
    end
  end

  @impl true
  def evaluate(market_data, state) do
    current_price = Condition.get_price(market_data)

    if is_nil(current_price) do
      {false, state}
    else
      {met?, new_state} = check_condition(current_price, state)
      {met?, %{new_state | last_price: current_price}}
    end
  end

  @impl true
  def type, do: :start

  @impl true
  def describe(state) do
    op_desc =
      case state.operator do
        "above" -> "is above"
        "below" -> "is below"
        "crosses_above" -> "crosses above"
        "crosses_below" -> "crosses below"
        _ -> state.operator
      end

    "Price #{op_desc} #{Decimal.to_string(state.threshold)}"
  end

  # Private functions

  defp check_condition(current_price, %{operator: "above", threshold: threshold} = state) do
    met? = Decimal.compare(current_price, threshold) == :gt
    {met?, state}
  end

  defp check_condition(current_price, %{operator: "below", threshold: threshold} = state) do
    met? = Decimal.compare(current_price, threshold) == :lt
    {met?, state}
  end

  defp check_condition(
         current_price,
         %{operator: "crosses_above", threshold: threshold, last_price: last_price} = state
       ) do
    if is_nil(last_price) do
      {false, state}
    else
      was_below = Decimal.compare(last_price, threshold) in [:lt, :eq]
      is_above = Decimal.compare(current_price, threshold) == :gt
      met? = was_below and is_above
      {met?, state}
    end
  end

  defp check_condition(
         current_price,
         %{operator: "crosses_below", threshold: threshold, last_price: last_price} = state
       ) do
    if is_nil(last_price) do
      {false, state}
    else
      was_above = Decimal.compare(last_price, threshold) in [:gt, :eq]
      is_below = Decimal.compare(current_price, threshold) == :lt
      met? = was_above and is_below
      {met?, state}
    end
  end

  defp check_condition(_current_price, state) do
    {false, state}
  end
end
