defmodule TradingEngine.Trader do
  @moduledoc """
  GenServer that manages trading for a single account.
  
  One Trader process per account, supervised by AccountSupervisor.
  Handles strategy execution, order management, and position tracking.
  """
  use GenServer
  require Logger

  alias DataCollector.BinanceClient
  alias TradingEngine.{RiskManager, Strategy}
  alias SharedData.{Config, Types}

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    setting_id = Keyword.fetch!(opts, :setting_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(setting_id))
  end

  @spec get_state(Types.account_id()) :: map()
  def get_state(account_id) do
    # Fast timeout for simple state read
    GenServer.call(via_tuple(account_id), :get_state, Config.timeout(:fast))
  end

  @spec place_order(Types.account_id(), Types.order_params()) :: Types.result(Types.order())
  def place_order(account_id, order_params) do
    # Longer timeout because involves external API call
    GenServer.call(via_tuple(account_id), {:place_order, order_params}, Config.timeout(:api))
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    setting_id = Keyword.fetch!(opts, :setting_id)
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    strategy = Keyword.fetch!(opts, :strategy)
    strategy_config = Keyword.fetch!(opts, :strategy_config)

    symbol = strategy_config["symbol"] || "BTCUSDT"

    Logger.info("Starting Trader for setting #{setting_id}, account #{account_id}, symbol #{symbol}")

    # Get strategy requirements to determine subscriptions
    requirements = Strategy.get_requirements(strategy, strategy_config)
    Logger.info("Strategy requirements: ticks=#{requirements.ticks}, timers=#{inspect(requirements.timers)}, executions=#{requirements.executions}")

    # Subscribe to ticker stream only if strategy needs ticks
    subscribed_to_ticks = if requirements.ticks do
      case DataCollector.TickerStream.subscribe(symbol) do
        {:ok, count} ->
          Logger.info("Subscribed to ticker stream for #{symbol} (subscribers: #{count})")
          Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")
          true

        {:error, reason} ->
          Logger.warning("Failed to subscribe to ticker stream for #{symbol}: #{inspect(reason)}")
          false
      end
    else
      Logger.info("Strategy does not require ticks, skipping ticker subscription")
      false
    end

    # Subscribe to order updates if strategy needs executions
    if requirements.executions do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")
    end

    # Setup timers based on strategy requirements
    timer_refs = for interval <- requirements.timers do
      ref = make_ref()
      Process.send_after(self(), {:strategy_timer, ref, interval}, interval)
      Logger.info("Scheduled timer with interval #{interval}ms")
      {ref, interval}
    end

    # Initialize strategy
    {:ok, strategy_state} = strategy.init(strategy_config)

    state = %{
      account_id: account_id,
      setting_id: setting_id,
      api_key: api_key,
      secret_key: secret_key,
      strategy: strategy,
      strategy_state: strategy_state,
      strategy_config: strategy_config,
      symbol: symbol,
      positions: %{},
      orders: %{},
      subscribed_to_ticks: subscribed_to_ticks,
      timer_refs: timer_refs
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

            # Broadcast order created event
            Phoenix.PubSub.broadcast(
              BinanceSystem.PubSub,
              "orders:#{state.account_id}",
              {:order_created, order}
            )

            Phoenix.PubSub.broadcast(
              BinanceSystem.PubSub,
              "orders:all",
              {:order_created, order}
            )

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
      # Broadcast order status updates
      order_status = execution["X"]

      case order_status do
        "FILLED" ->
          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:#{state.account_id}",
            {:order_filled, execution}
          )

          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:all",
            {:order_filled, execution}
          )

        "CANCELED" ->
          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:#{state.account_id}",
            {:order_cancelled, execution}
          )

          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:all",
            {:order_cancelled, execution}
          )

        "PARTIALLY_FILLED" ->
          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:#{state.account_id}",
            {:order_partially_filled, execution}
          )

          Phoenix.PubSub.broadcast(
            BinanceSystem.PubSub,
            "orders:all",
            {:order_partially_filled, execution}
          )

        _ ->
          :ok
      end

      {action, new_strategy_state} = state.strategy.on_execution(execution, state.strategy_state)

      new_state = %{state | strategy_state: new_strategy_state}
      final_state = execute_action(action, new_state)

      {:noreply, final_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:strategy_timer, ref, interval}, state) do
    # Check if strategy implements on_timer callback
    if function_exported?(state.strategy, :on_timer, 2) do
      Logger.debug("Timer fired for #{state.symbol}, interval: #{interval}ms")

      {action, new_strategy_state} = state.strategy.on_timer(ref, state.strategy_state)

      # Re-schedule the timer
      Process.send_after(self(), {:strategy_timer, ref, interval}, interval)

      new_state = %{state | strategy_state: new_strategy_state}
      final_state = execute_action(action, new_state)

      {:noreply, final_state}
    else
      # Strategy doesn't implement on_timer, just re-schedule
      Process.send_after(self(), {:strategy_timer, ref, interval}, interval)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Trader terminating for #{state.symbol}, reason: #{inspect(reason)}")

    # Cancel open orders for Grid strategy on stop
    if state.strategy == TradingEngine.Strategies.Grid do
      cancel_open_orders_on_stop(state)
    end

    # Only unsubscribe from ticker stream if we subscribed
    if state.subscribed_to_ticks do
      DataCollector.TickerStream.unsubscribe(state.symbol)
    end

    :ok
  end

  defp cancel_open_orders_on_stop(state) do
    Logger.info("Grid cleanup: Cancelling open orders for #{state.symbol}")

    case BinanceClient.get_open_orders(state.api_key, state.secret_key, state.symbol) do
      {:ok, orders} when orders != [] ->
        Enum.each(orders, fn order ->
          case BinanceClient.cancel_order(state.api_key, state.secret_key, state.symbol, order["orderId"]) do
            {:ok, _} ->
              Logger.info("Cancelled order #{order["orderId"]}")
            {:error, reason} ->
              Logger.warning("Failed to cancel order #{order["orderId"]}: #{inspect(reason)}")
          end
        end)
        Logger.info("Grid cleanup: Cancelled #{length(orders)} orders")

      {:ok, []} ->
        Logger.info("Grid cleanup: No open orders to cancel")

      {:error, reason} ->
        Logger.error("Grid cleanup: Failed to get open orders: #{inspect(reason)}")
    end
  end

  # Private functions

  @spec execute_action(Types.strategy_action(), map()) :: map()
  defp execute_action(:noop, state), do: state

  # Handle batch orders (list of order params)
  defp execute_action({:place_order, order_params_list}, state) when is_list(order_params_list) do
    Enum.reduce(order_params_list, state, fn order_params, acc_state ->
      case handle_call({:place_order, order_params}, nil, acc_state) do
        {:reply, _, new_state} -> new_state
        _ -> acc_state
      end
    end)
  end

  # Handle single order
  defp execute_action({:place_order, order_params}, state) when is_map(order_params) do
    case handle_call({:place_order, order_params}, nil, state) do
      {:reply, _, new_state} -> new_state
    end
  end

  @spec via_tuple(Types.account_id()) :: Types.genserver_name()
  defp via_tuple(account_id) do
    {:via, Registry, {TradingEngine.TraderRegistry, account_id}}
  end
end
