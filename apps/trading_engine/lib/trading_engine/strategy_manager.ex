defmodule TradingEngine.StrategyManager do
  @moduledoc """
  GenServer that manages the lifecycle of Trader processes.

  Listens to PubSub "strategy_updates" topic and:
  - Starts Trader when strategy is activated
  - Stops Trader when strategy is deactivated
  - Restores active strategies on application startup
  - Monitors Trader processes for crashes
  """
  use GenServer
  require Logger

  alias SharedData.{Settings, Config}
  alias TradingEngine.{AccountSupervisor, StrategyLoader, PendingStrategiesManager, StopConditionsMonitor}
  alias TradingEngine.Conditions.ConditionEvaluator

  @topic "strategy_updates"

  # Client API

  @doc """
  Starts the StrategyManager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns a map of currently running strategies.
  """
  @spec get_running_strategies() :: map()
  def get_running_strategies do
    GenServer.call(__MODULE__, :get_running_strategies, Config.timeout(:fast))
  end

  @doc """
  Checks if a specific strategy is running.
  """
  @spec is_running?(String.t()) :: boolean()
  def is_running?(setting_id) do
    GenServer.call(__MODULE__, {:is_running, setting_id}, Config.timeout(:fast))
  end

  @doc """
  Manually starts a strategy (for testing or manual intervention).
  """
  @spec start_strategy(String.t()) :: {:ok, pid()} | {:error, term()}
  def start_strategy(setting_id) do
    GenServer.call(__MODULE__, {:start_strategy, setting_id}, Config.timeout(:api))
  end

  @doc """
  Manually stops a strategy.
  """
  @spec stop_strategy(String.t()) :: :ok | {:error, term()}
  def stop_strategy(setting_id) do
    GenServer.call(__MODULE__, {:stop_strategy, setting_id}, Config.timeout(:fast))
  end

  @doc """
  Reloads a strategy - stops and starts it again.
  Useful after changing strategy code (hot code reload).
  """
  @spec reload_strategy(String.t()) :: {:ok, pid()} | {:error, term()}
  def reload_strategy(setting_id) do
    with :ok <- stop_strategy(setting_id) do
      :timer.sleep(200)
      start_strategy(setting_id)
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to strategy updates
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, @topic)

    # Schedule startup restoration (give other services time to start)
    Process.send_after(self(), :restore_active_strategies, 1000)

    state = %{
      running_traders: %{},
      monitors: %{},
      settings_cache: %{}
    }

    Logger.info("StrategyManager started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_running_strategies, _from, state) do
    running = Map.keys(state.running_traders)
    {:reply, running, state}
  end

  @impl true
  def handle_call({:is_running, setting_id}, _from, state) do
    {:reply, Map.has_key?(state.running_traders, setting_id), state}
  end

  @impl true
  def handle_call({:start_strategy, setting_id}, _from, state) do
    case Settings.get_setting(setting_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      setting ->
        case start_trader_for_setting(setting) do
          {:ok, pid} ->
            new_state = add_running_trader(state, setting, pid)
            {:reply, {:ok, pid}, new_state}

          {:error, reason} = error ->
            Logger.error("Failed to start strategy #{setting_id}: #{inspect(reason)}")
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:stop_strategy, setting_id}, _from, state) do
    new_state = stop_trader_for_setting(state, setting_id)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:restore_active_strategies, state) do
    Logger.info("Restoring active strategies...")

    active_settings = Settings.list_active_settings()
    Logger.info("Found #{length(active_settings)} active strategies to restore")

    new_state =
      Enum.reduce(active_settings, state, fn setting, acc ->
        case start_trader_for_setting(setting) do
          {:ok, pid} ->
            Logger.info("Restored strategy #{setting.id} (#{setting.strategy_name})")
            add_running_trader(acc, setting, pid)

          {:error, reason} ->
            Logger.error(
              "Failed to restore strategy #{setting.id}: #{inspect(reason)}. Deactivating."
            )

            # Deactivate failed strategy in database
            Settings.deactivate_setting(setting)
            acc
        end
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:strategy_activated, setting}, state) do
    Logger.info("Strategy activated: #{setting.id} (#{setting.strategy_name})")

    # Check if already running
    if Map.has_key?(state.running_traders, setting.id) do
      Logger.warning("Strategy #{setting.id} is already running, ignoring activation")
      {:noreply, state}
    else
      # Reload setting to get fresh config
      setting = Settings.get_setting_with_credentials(setting.id) || setting

      # Check if there are start conditions
      start_conditions = setting.config["start_conditions"]

      if ConditionEvaluator.has_conditions?(start_conditions) do
        # Route to PendingStrategiesManager
        Logger.info("Strategy #{setting.id} has start conditions, adding to pending")
        PendingStrategiesManager.add_pending(setting)
        {:noreply, state}
      else
        # No start conditions, start immediately
        case start_trader_for_setting(setting) do
          {:ok, pid} ->
            new_state = add_running_trader(state, setting, pid)
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("Failed to start strategy #{setting.id}: #{inspect(reason)}")

            # Broadcast strategy error event
            Phoenix.PubSub.broadcast(
              BinanceSystem.PubSub,
              "strategies:all",
              {:strategy_error, setting.id, reason}
            )

            # Deactivate in database since we couldn't start it
            Settings.deactivate_setting(setting)
            {:noreply, state}
        end
      end
    end
  end

  @impl true
  def handle_info({:strategy_deactivated, setting}, state) do
    Logger.info("Strategy deactivated: #{setting.id} (#{setting.strategy_name})")
    # Remove from pending if it was waiting for conditions
    PendingStrategiesManager.remove_pending(setting.id)
    # Stop the trader if running
    new_state = stop_trader_for_setting(state, setting.id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:strategy_auto_stopped, setting, reason}, state) do
    Logger.info("Strategy auto-stopped: #{setting.id} reason: #{inspect(reason)}")
    new_state = stop_trader_for_setting(state, setting.id)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:conditions_met, setting}, state) do
    # Start condition was met, now actually start the trader
    Logger.info("Start conditions met for strategy #{setting.id}")

    case start_trader_for_setting(setting) do
      {:ok, pid} ->
        new_state = add_running_trader(state, setting, pid)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to start strategy after conditions met: #{inspect(reason)}")

        # Broadcast strategy error event
        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "strategies:all",
          {:strategy_error, setting.id, reason}
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find which setting this monitor belongs to
    case find_setting_by_monitor(state, ref) do
      nil ->
        {:noreply, state}

      setting_id ->
        Logger.warning(
          "Trader for setting #{setting_id} crashed (pid: #{inspect(pid)}): #{inspect(reason)}"
        )

        new_state = remove_running_trader(state, setting_id)

        # Optionally restart based on reason
        case reason do
          :normal ->
            :ok

          :shutdown ->
            :ok

          {:shutdown, _} ->
            :ok

          _ ->
            # Unexpected crash - mark as inactive
            case Settings.get_setting(setting_id) do
              nil -> :ok
              setting -> Settings.deactivate_setting(setting)
            end
        end

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("StrategyManager received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp start_trader_for_setting(setting) do
    # Reload setting with preloaded associations
    setting = Settings.get_setting_with_credentials(setting.id)

    case setting do
      nil ->
        {:error, :setting_not_found}

      %{account: nil} ->
        {:error, :account_not_found}

      %{account: %{api_credential: nil}} ->
        {:error, :credentials_not_found}

      %{account: account} ->
        # Get the strategy module
        case StrategyLoader.get_strategy_module_safe(setting.strategy_name) do
          {:error, :unknown_strategy} ->
            {:error, {:unknown_strategy, setting.strategy_name}}

          {:ok, strategy_module} ->
            # Prepare config with symbol default if missing
            config = ensure_symbol_in_config(setting.config)

            opts = [
              setting_id: setting.id,
              account_id: account.id,
              api_key: account.api_credential.api_key,
              secret_key: account.api_credential.secret_key,
              strategy: strategy_module,
              strategy_config: config
            ]

            AccountSupervisor.start_trader(account.id, opts)
        end
    end
  end

  defp ensure_symbol_in_config(config) when is_map(config) do
    if Map.has_key?(config, "symbol") do
      config
    else
      Map.put(config, "symbol", "BTCUSDT")
    end
  end

  defp add_running_trader(state, setting, pid) do
    ref = Process.monitor(pid)

    # Register with StopConditionsMonitor if stop conditions exist
    if ConditionEvaluator.has_conditions?(setting.config["stop_conditions"]) do
      entry_state = %{
        entry_price: nil,
        position_size: Decimal.new(0),
        started_at: DateTime.utc_now()
      }

      StopConditionsMonitor.monitor_strategy(setting, entry_state)
      Logger.info("Registered strategy #{setting.id} for stop condition monitoring")
    end

    # Broadcast strategy started event
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "strategies:all",
      {:strategy_started, setting.id, %{
        strategy_name: setting.strategy_name,
        account_id: setting.account_id,
        config: setting.config,
        started_at: DateTime.utc_now()
      }}
    )

    %{
      state
      | running_traders: Map.put(state.running_traders, setting.id, pid),
        monitors: Map.put(state.monitors, setting.id, ref),
        settings_cache: Map.put(state.settings_cache, setting.id, setting)
    }
  end

  defp stop_trader_for_setting(state, setting_id) do
    # Unregister from StopConditionsMonitor
    StopConditionsMonitor.unmonitor_strategy(setting_id)

    case Map.get(state.running_traders, setting_id) do
      nil ->
        Logger.debug("Strategy #{setting_id} is not running, nothing to stop")
        state

      _pid ->
        # Stop trader by setting_id
        case AccountSupervisor.stop_trader(setting_id) do
          :ok ->
            Logger.info("Stopped trader for setting #{setting_id}")

          {:error, :not_found} ->
            Logger.debug("Trader already stopped for setting #{setting_id}")
        end

        # Broadcast strategy stopped event
        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "strategies:all",
          {:strategy_stopped, setting_id}
        )

        remove_running_trader(state, setting_id)
    end
  end

  defp remove_running_trader(state, setting_id) do
    # Demonitor if monitor exists
    case Map.get(state.monitors, setting_id) do
      nil -> :ok
      ref -> Process.demonitor(ref, [:flush])
    end

    %{
      state
      | running_traders: Map.delete(state.running_traders, setting_id),
        monitors: Map.delete(state.monitors, setting_id),
        settings_cache: Map.delete(state.settings_cache, setting_id)
    }
  end

  defp find_setting_by_monitor(state, ref) do
    Enum.find_value(state.monitors, fn {setting_id, monitor_ref} ->
      if monitor_ref == ref, do: setting_id
    end)
  end
end
