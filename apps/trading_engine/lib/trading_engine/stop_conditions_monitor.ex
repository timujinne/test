defmodule TradingEngine.StopConditionsMonitor do
  @moduledoc """
  Monitors running strategies for stop conditions.

  When a stop condition is met, broadcasts {:strategy_auto_stopped, setting, reason}
  to the strategy_updates topic.
  """
  use GenServer
  require Logger

  alias TradingEngine.Conditions.ConditionEvaluator
  alias SharedData.Settings

  @topic "strategy_updates"
  @check_interval 60_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start monitoring a strategy for stop conditions.
  """
  @spec monitor_strategy(map(), map()) :: :ok
  def monitor_strategy(setting, entry_state \\ %{}) do
    GenServer.cast(__MODULE__, {:monitor, setting, entry_state})
  end

  @doc """
  Stop monitoring a strategy.
  """
  @spec unmonitor_strategy(String.t()) :: :ok
  def unmonitor_strategy(setting_id) do
    GenServer.cast(__MODULE__, {:unmonitor, setting_id})
  end

  @doc """
  Update P&L data for a strategy.
  """
  @spec update_pnl(String.t(), map()) :: :ok
  def update_pnl(setting_id, pnl_data) do
    GenServer.cast(__MODULE__, {:update_pnl, setting_id, pnl_data})
  end

  @doc """
  Get list of monitored strategies.
  """
  @spec list_monitored() :: [String.t()]
  def list_monitored do
    GenServer.call(__MODULE__, :list_monitored)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to strategy updates to track when strategies start/stop
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, @topic)

    # Schedule periodic check for time-based conditions
    :timer.send_interval(@check_interval, self(), :check_time_conditions)

    state = %{
      monitored: %{},
      daily_pnl_by_account: %{},
      subscribed_symbols: MapSet.new()
    }

    Logger.info("StopConditionsMonitor started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:monitor, setting, entry_state}, state) do
    stop_conditions = setting.config["stop_conditions"]

    if ConditionEvaluator.has_conditions?(stop_conditions) do
      case ConditionEvaluator.init(stop_conditions) do
        {:ok, condition_state} ->
          symbol = setting.config["symbol"] || "BTCUSDT"

          # Subscribe to market data if not already
          new_subscribed =
            if MapSet.member?(state.subscribed_symbols, symbol) do
              state.subscribed_symbols
            else
              Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")
              MapSet.put(state.subscribed_symbols, symbol)
            end

          monitored_entry = %{
            setting: setting,
            entry_state: entry_state,
            condition_state: condition_state,
            pnl: Decimal.new(0),
            pnl_percent: Decimal.new(0),
            entry_price: entry_state[:entry_price],
            position_size: entry_state[:position_size] || Decimal.new(0)
          }

          new_monitored = Map.put(state.monitored, setting.id, monitored_entry)

          Logger.info(
            "Monitoring strategy #{setting.id} for stop conditions: #{ConditionEvaluator.describe(condition_state)}"
          )

          {:noreply, %{state | monitored: new_monitored, subscribed_symbols: new_subscribed}}

        {:error, reason} ->
          Logger.error("Failed to init stop conditions for #{setting.id}: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:unmonitor, setting_id}, state) do
    new_monitored = Map.delete(state.monitored, setting_id)
    {:noreply, %{state | monitored: new_monitored}}
  end

  @impl true
  def handle_cast({:update_pnl, setting_id, pnl_data}, state) do
    case Map.get(state.monitored, setting_id) do
      nil ->
        {:noreply, state}

      entry ->
        updated_entry = %{entry |
          pnl: pnl_data[:pnl] || entry.pnl,
          pnl_percent: pnl_data[:pnl_percent] || entry.pnl_percent
        }

        new_monitored = Map.put(state.monitored, setting_id, updated_entry)

        # Also update daily P&L for the account
        account_id = entry.setting.account_id
        current_daily = Map.get(state.daily_pnl_by_account, account_id, Decimal.new(0))
        # This is a simplification - real implementation would track trades
        new_daily_pnl = Map.put(state.daily_pnl_by_account, account_id, current_daily)

        {:noreply, %{state | monitored: new_monitored, daily_pnl_by_account: new_daily_pnl}}
    end
  end

  @impl true
  def handle_call(:list_monitored, _from, state) do
    {:reply, Map.keys(state.monitored), state}
  end

  @impl true
  def handle_info({:ticker, market_data}, state) do
    symbol = market_data["s"]
    current_price = get_price(market_data)

    # Check stop conditions for strategies trading this symbol
    {to_stop, updated_monitored} =
      state.monitored
      |> Enum.reduce({[], %{}}, fn {id, entry}, {stop_acc, mon_acc} ->
        if entry.setting.config["symbol"] == symbol do
          # Calculate current P&L
          {pnl, pnl_percent} = calculate_pnl(entry, current_price)

          # Build evaluation data
          eval_data = %{
            "pnl" => Decimal.to_float(pnl),
            "pnl_percent" => Decimal.to_float(pnl_percent),
            "daily_pnl" => get_daily_pnl(state, entry.setting.account_id),
            "c" => market_data["c"]
          }

          # Evaluate stop conditions
          {met?, new_cond_state} =
            ConditionEvaluator.evaluate(
              entry.setting.config["stop_conditions"],
              eval_data,
              entry.condition_state
            )

          updated_entry = %{entry |
            pnl: pnl,
            pnl_percent: pnl_percent,
            condition_state: new_cond_state
          }

          if met? do
            reason = determine_stop_reason(entry.setting.config["stop_conditions"])
            {[{id, entry.setting, reason} | stop_acc], mon_acc}
          else
            {stop_acc, Map.put(mon_acc, id, updated_entry)}
          end
        else
          {stop_acc, Map.put(mon_acc, id, entry)}
        end
      end)

    # Trigger stops
    Enum.each(to_stop, fn {_id, setting, reason} ->
      trigger_auto_stop(setting, reason)
    end)

    # Remove stopped strategies from monitored
    final_monitored =
      Enum.reduce(to_stop, updated_monitored, fn {id, _, _}, acc ->
        Map.delete(acc, id)
      end)

    {:noreply, %{state | monitored: final_monitored}}
  end

  @impl true
  def handle_info(:check_time_conditions, state) do
    # Check time-based stop conditions
    {to_stop, updated_monitored} =
      state.monitored
      |> Enum.reduce({[], %{}}, fn {id, entry}, {stop_acc, mon_acc} ->
        # Build minimal eval data for time conditions
        eval_data = %{
          "pnl" => Decimal.to_float(entry.pnl),
          "pnl_percent" => Decimal.to_float(entry.pnl_percent)
        }

        {met?, new_cond_state} =
          ConditionEvaluator.evaluate(
            entry.setting.config["stop_conditions"],
            eval_data,
            entry.condition_state
          )

        updated_entry = %{entry | condition_state: new_cond_state}

        if met? do
          {[{id, entry.setting, :time_stop} | stop_acc], mon_acc}
        else
          {stop_acc, Map.put(mon_acc, id, updated_entry)}
        end
      end)

    # Trigger stops
    Enum.each(to_stop, fn {_id, setting, reason} ->
      trigger_auto_stop(setting, reason)
    end)

    final_monitored =
      Enum.reduce(to_stop, updated_monitored, fn {id, _, _}, acc ->
        Map.delete(acc, id)
      end)

    {:noreply, %{state | monitored: final_monitored}}
  end

  @impl true
  def handle_info({:conditions_met, setting}, state) do
    # Strategy started, begin monitoring for stop conditions
    monitor_strategy(setting)
    {:noreply, state}
  end

  @impl true
  def handle_info({:strategy_deactivated, setting}, state) do
    # Strategy stopped, remove from monitoring
    new_monitored = Map.delete(state.monitored, setting.id)
    {:noreply, %{state | monitored: new_monitored}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp get_price(market_data) do
    case market_data["c"] do
      nil -> Decimal.new(0)
      p when is_binary(p) -> Decimal.new(p)
      p when is_number(p) -> Decimal.new(p)
      _ -> Decimal.new(0)
    end
  end

  defp calculate_pnl(entry, current_price) do
    entry_price = entry.entry_price || current_price
    position_size = entry.position_size || Decimal.new(0)

    if Decimal.compare(position_size, Decimal.new(0)) == :eq or
       Decimal.compare(entry_price, Decimal.new(0)) == :eq do
      {Decimal.new(0), Decimal.new(0)}
    else
      price_diff = Decimal.sub(current_price, entry_price)
      pnl = Decimal.mult(price_diff, position_size)
      pnl_percent = Decimal.mult(Decimal.div(price_diff, entry_price), Decimal.new(100))
      {pnl, pnl_percent}
    end
  end

  defp get_daily_pnl(state, account_id) do
    state.daily_pnl_by_account
    |> Map.get(account_id, Decimal.new(0))
    |> Decimal.to_float()
  end

  defp determine_stop_reason(stop_conditions) do
    conditions = stop_conditions["conditions"] || []

    cond do
      Enum.any?(conditions, &(&1["type"] == "take_profit")) -> :take_profit
      Enum.any?(conditions, &(&1["type"] == "stop_loss")) -> :stop_loss
      Enum.any?(conditions, &(&1["type"] == "max_daily_loss")) -> :max_daily_loss
      Enum.any?(conditions, &(&1["type"] == "time_stop")) -> :time_stop
      true -> :unknown
    end
  end

  defp trigger_auto_stop(setting, reason) do
    Logger.info("Auto-stopping strategy #{setting.id} due to: #{reason}")

    # Deactivate in database
    Settings.deactivate_setting(setting)

    # Broadcast to other components
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      @topic,
      {:strategy_auto_stopped, setting, reason}
    )
  end
end
