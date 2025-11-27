defmodule TradingEngine.Conditions.TimeCondition do
  @moduledoc """
  Time-based condition for trading within specific hours.

  Config:
  - start_hour: Hour to start trading (0-23, UTC by default)
  - end_hour: Hour to stop trading (0-23, UTC by default)
  - timezone: Optional timezone (default: "UTC")
  - days: Optional list of days to trade (default: all days)
    - 1 = Monday, 7 = Sunday
  """

  @behaviour TradingEngine.Conditions.Condition

  alias TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    start_hour = Condition.parse_number(config["start_hour"]) || 0
    end_hour = Condition.parse_number(config["end_hour"]) || 23
    timezone = config["timezone"] || "UTC"
    days = config["days"] || [1, 2, 3, 4, 5, 6, 7]

    state = %{
      start_hour: start_hour,
      end_hour: end_hour,
      timezone: timezone,
      days: days
    }

    {:ok, state}
  end

  @impl true
  def evaluate(_market_data, state) do
    now = get_current_time(state.timezone)
    hour = now.hour
    day = Date.day_of_week(DateTime.to_date(now))

    # Check if current day is a trading day
    day_ok = day in state.days

    # Check if current hour is within trading hours
    hour_ok = is_within_hours?(hour, state.start_hour, state.end_hour)

    met? = day_ok and hour_ok
    {met?, state}
  end

  @impl true
  def type, do: :start

  @impl true
  def describe(state) do
    days_str =
      case state.days do
        [1, 2, 3, 4, 5, 6, 7] -> "every day"
        [1, 2, 3, 4, 5] -> "weekdays"
        [6, 7] -> "weekends"
        days -> "days #{Enum.join(days, ", ")}"
      end

    "Trade #{days_str} from #{format_hour(state.start_hour)} to #{format_hour(state.end_hour)} #{state.timezone}"
  end

  # Private functions

  defp get_current_time("UTC"), do: DateTime.utc_now()

  defp get_current_time(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp is_within_hours?(current_hour, start_hour, end_hour) when start_hour <= end_hour do
    # Normal case: e.g., 9-17
    current_hour >= start_hour and current_hour < end_hour
  end

  defp is_within_hours?(current_hour, start_hour, end_hour) do
    # Overnight case: e.g., 22-6 (spans midnight)
    current_hour >= start_hour or current_hour < end_hour
  end

  defp format_hour(hour) do
    h = rem(hour, 12)
    h = if h == 0, do: 12, else: h
    suffix = if hour < 12, do: "AM", else: "PM"
    "#{h}:00 #{suffix}"
  end
end
