defmodule TradingEngine.Conditions.VolumeCondition do
  @moduledoc """
  Volume-based condition for starting strategies when market has sufficient activity.

  Config:
  - value: Volume threshold
  - operator: "above" or "below" (default: "above")
  - period: "24h" (currently only 24h volume is supported from ticker)
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    threshold = Condition.parse_number(config["value"] || config["threshold"])
    operator = config["operator"] || "above"

    if is_nil(threshold) do
      {:error, :invalid_threshold}
    else
      state = %{
        threshold: Decimal.new(threshold),
        operator: operator
      }

      {:ok, state}
    end
  end

  @impl true
  def evaluate(market_data, state) do
    current_volume = Condition.get_volume(market_data)

    if is_nil(current_volume) do
      {false, state}
    else
      met? = check_condition(current_volume, state)
      {met?, state}
    end
  end

  @impl true
  def type, do: :start

  @impl true
  def describe(state) do
    op_desc = if state.operator == "above", do: "above", else: "below"
    "24h volume is #{op_desc} #{Decimal.to_string(state.threshold)}"
  end

  # Private functions

  defp check_condition(current_volume, %{operator: "above", threshold: threshold}) do
    Decimal.compare(current_volume, threshold) == :gt
  end

  defp check_condition(current_volume, %{operator: "below", threshold: threshold}) do
    Decimal.compare(current_volume, threshold) == :lt
  end

  defp check_condition(_current_volume, _state), do: false
end
