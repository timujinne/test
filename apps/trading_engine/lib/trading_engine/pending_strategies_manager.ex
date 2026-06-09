defmodule TradingEngine.PendingStrategiesManager do
  @moduledoc """
  Manages strategies that are waiting for start conditions to be met.

  When a strategy is activated but has start conditions configured,
  it's added to the pending list. This GenServer monitors market data
  and triggers the strategy when conditions are met.
  """
  use GenServer
  require Logger

  alias TradingEngine.Conditions.ConditionEvaluator

  @topic "strategy_updates"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a strategy to the pending list.
  """
  @spec add_pending(map()) :: :ok
  def add_pending(setting) do
    GenServer.cast(__MODULE__, {:add_pending, setting})
  end

  @doc """
  Remove a strategy from the pending list.
  """
  @spec remove_pending(String.t()) :: :ok
  def remove_pending(setting_id) do
    GenServer.cast(__MODULE__, {:remove_pending, setting_id})
  end

  @doc """
  Get list of pending strategy IDs.
  """
  @spec list_pending() :: [String.t()]
  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  @doc """
  Check if a strategy is pending.
  """
  @spec is_pending?(String.t()) :: boolean()
  def is_pending?(setting_id) do
    GenServer.call(__MODULE__, {:is_pending, setting_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      pending: %{},
      subscribed_symbols: MapSet.new()
    }

    Logger.info("PendingStrategiesManager started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_pending, setting}, state) do
    symbol = get_symbol(setting)
    start_conditions = setting.config["start_conditions"]

    # Check if there are actually start conditions
    if ConditionEvaluator.has_conditions?(start_conditions) do
      # Initialize condition evaluator
      case ConditionEvaluator.init(start_conditions) do
        {:ok, condition_state} ->
          # Subscribe to market data if not already
          new_subscribed =
            if MapSet.member?(state.subscribed_symbols, symbol) do
              state.subscribed_symbols
            else
              Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")
              Logger.info("Subscribed to market:#{symbol} for pending strategies")
              MapSet.put(state.subscribed_symbols, symbol)
            end

          new_pending = Map.put(state.pending, setting.id, {setting, condition_state})

          Logger.info(
            "Added pending strategy #{setting.id} (#{setting.strategy_name}) waiting for: #{ConditionEvaluator.describe(condition_state)}"
          )

          {:noreply, %{state | pending: new_pending, subscribed_symbols: new_subscribed}}

        {:error, reason} ->
          Logger.error("Failed to init conditions for strategy #{setting.id}: #{inspect(reason)}")
          # Start immediately if conditions can't be initialized
          notify_conditions_met(setting)
          {:noreply, state}
      end
    else
      # No start conditions, notify immediately
      Logger.info("Strategy #{setting.id} has no start conditions, starting immediately")
      notify_conditions_met(setting)
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:remove_pending, setting_id}, state) do
    new_pending = Map.delete(state.pending, setting_id)
    Logger.debug("Removed pending strategy #{setting_id}")
    {:noreply, %{state | pending: new_pending}}
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    {:reply, Map.keys(state.pending), state}
  end

  @impl true
  def handle_call({:is_pending, setting_id}, _from, state) do
    {:reply, Map.has_key?(state.pending, setting_id), state}
  end

  @impl true
  def handle_info({:ticker, market_data}, state) do
    symbol = market_data["s"]

    # Find pending strategies for this symbol
    {to_check, _others} =
      state.pending
      |> Enum.split_with(fn {_id, {setting, _cond_state}} ->
        get_symbol(setting) == symbol
      end)

    # Evaluate conditions for each
    {started, still_pending} =
      Enum.reduce(to_check, {[], []}, fn {id, {setting, condition_state}},
                                         {started_acc, pending_acc} ->
        {met?, new_cond_state} =
          ConditionEvaluator.evaluate(
            setting.config["start_conditions"],
            market_data,
            condition_state
          )

        if met? do
          Logger.info("Start conditions met for strategy #{id}")
          notify_conditions_met(setting)
          {started_acc ++ [id], pending_acc}
        else
          {started_acc, pending_acc ++ [{id, {setting, new_cond_state}}]}
        end
      end)

    # Update pending map
    new_pending =
      state.pending
      |> Map.drop(started)
      |> Map.merge(Map.new(still_pending))

    {:noreply, %{state | pending: new_pending}}
  end

  @impl true
  def handle_info({:trade, _trade_data}, state) do
    # We primarily use ticker data for conditions, ignore individual trades
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("PendingStrategiesManager received: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp get_symbol(setting) do
    setting.config["symbol"] || "BTCUSDT"
  end

  defp notify_conditions_met(setting) do
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      @topic,
      {:conditions_met, setting}
    )
  end
end
