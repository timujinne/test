defmodule TradingEngine.Conditions.TimeStopCondition do
  @moduledoc """
  Time-based stop condition for automatically stopping a strategy at a specific time.

  Config:
  - stop_at: Time to stop (e.g., "17:00" or "23:30")
  - timezone: Timezone (default: "UTC")
  """

  @behaviour TradingEngine.Conditions.Condition

  @impl true
  def init(config) do
    stop_at = config["stop_at"]
    timezone = config["timezone"] || "UTC"

    case parse_time(stop_at) do
      {:ok, {hour, minute}} ->
        {:ok,
         %{
           stop_hour: hour,
           stop_minute: minute,
           timezone: timezone,
           triggered_today: false,
           last_check_date: nil
         }}

      :error ->
        {:error, :invalid_time}
    end
  end

  @impl true
  def evaluate(_market_data, state) do
    now = get_current_time(state.timezone)
    today = DateTime.to_date(now)

    # Reset triggered flag if it's a new day
    state =
      if state.last_check_date != today do
        %{state | triggered_today: false, last_check_date: today}
      else
        state
      end

    # Don't trigger again if already triggered today
    if state.triggered_today do
      {false, state}
    else
      current_minutes = now.hour * 60 + now.minute
      stop_minutes = state.stop_hour * 60 + state.stop_minute

      met? = current_minutes >= stop_minutes

      if met? do
        {true, %{state | triggered_today: true}}
      else
        {false, state}
      end
    end
  end

  @impl true
  def type, do: :stop

  @impl true
  def describe(state) do
    "Stop at #{format_time(state.stop_hour, state.stop_minute)} #{state.timezone}"
  end

  # Private functions

  defp parse_time(nil), do: :error

  defp parse_time(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             true <- hour >= 0 and hour < 24,
             true <- minute >= 0 and minute < 60 do
          {:ok, {hour, minute}}
        else
          _ -> :error
        end

      [hour_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             true <- hour >= 0 and hour < 24 do
          {:ok, {hour, 0}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_time(_), do: :error

  defp get_current_time("UTC"), do: DateTime.utc_now()

  defp get_current_time(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp format_time(hour, minute) do
    h = String.pad_leading(Integer.to_string(hour), 2, "0")
    m = String.pad_leading(Integer.to_string(minute), 2, "0")
    "#{h}:#{m}"
  end
end
