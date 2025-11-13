defmodule TradingEngine.Trader do
  @moduledoc """
  GenServer that manages trading for a single account.
  
  One Trader process per account, supervised by AccountSupervisor.
  Handles strategy execution, order management, and position tracking.
  """
  use GenServer
  require Logger

  alias DataCollector.BinanceClient
  alias TradingEngine.OrderManager
  alias TradingEngine.PositionTracker
  alias TradingEngine.RiskManager

  # Client API

  def start_link(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(account_id))
  end

  def get_state(account_id) do
    GenServer.call(via_tuple(account_id), :get_state)
  end

  def place_order(account_id, order_params) do
    GenServer.call(via_tuple(account_id), {:place_order, order_params})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    strategy = Keyword.fetch!(opts, :strategy)
    strategy_config = Keyword.fetch!(opts, :strategy_config)

    Logger.info("Starting Trader for account #{account_id}")

    # Subscribe to market data and order updates
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{strategy_config["symbol"]}")
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")

    # Initialize strategy
    {:ok, strategy_state} = strategy.init(strategy_config)

    state = %{
      account_id: account_id,
      api_key: api_key,
      secret_key: secret_key,
      strategy: strategy,
      strategy_state: strategy_state,
      positions: %{},
      orders: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:place_order, order_params}, _from, state) do
    # Check risk management before placing order
    case RiskManager.check_order(order_params, state) do
      :ok ->
        case BinanceClient.create_order(state.api_key, state.secret_key, order_params) do
          {:ok, order} ->
            new_orders = Map.put(state.orders, order["orderId"], order)
            {:reply, {:ok, order}, %{state | orders: new_orders}}

          {:error, reason} = error ->
            Logger.error("Failed to place order: #{inspect(reason)}")
            {:reply, error, state}
        end

      {:error, reason} = error ->
        Logger.warning("Order rejected by risk manager: #{reason}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:ticker, market_data}, state) do
    # Pass market data to strategy
    {action, new_strategy_state} = state.strategy.on_tick(market_data, state.strategy_state)

    new_state = %{state | strategy_state: new_strategy_state}

    # Execute strategy action
    final_state = execute_action(action, new_state)

    {:noreply, final_state}
  end

  @impl true
  def handle_info({:execution_report, execution}, state) do
    # Check if this execution belongs to this account
    if execution["a"] == state.account_id do
      {action, new_strategy_state} = state.strategy.on_execution(execution, state.strategy_state)

      new_state = %{state | strategy_state: new_strategy_state}
      final_state = execute_action(action, new_state)

      {:noreply, final_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp execute_action(:noop, state), do: state

  defp execute_action({:place_order, order_params}, state) do
    case handle_call({:place_order, order_params}, nil, state) do
      {:reply, _, new_state} -> new_state
    end
  end

  defp via_tuple(account_id) do
    {:via, Registry, {TradingEngine.TraderRegistry, account_id}}
  end
end
