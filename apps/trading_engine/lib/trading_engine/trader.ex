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

    # Get ALL required symbols from strategy (supports multi-symbol strategies)
    symbols = Strategy.get_required_symbols(strategy, strategy_config)
    symbol = strategy_config["symbol"] || List.first(symbols) || "BTCUSDT"

    Logger.info("Starting Trader for setting #{setting_id}, account #{account_id}, symbols: #{inspect(symbols)}")

    # Add setting_id to strategy config for state persistence
    strategy_config = Map.put(strategy_config, "setting_id", setting_id)

    # Check for existing chain state and open orders (for recovery)
    recovery_info = check_for_recovery(setting_id, api_key, secret_key, symbol)
    strategy_config = if recovery_info do
      Logger.info("Found recovery state for setting #{setting_id}: #{inspect(recovery_info)}")
      Map.put(strategy_config, "_recovery", recovery_info)
    else
      strategy_config
    end

    # Get strategy requirements to determine subscriptions
    requirements = Strategy.get_requirements(strategy, strategy_config)
    Logger.info("Strategy requirements: ticks=#{requirements.ticks}, timers=#{inspect(requirements.timers)}, executions=#{requirements.executions}")

    # Subscribe to ticker streams for ALL symbols if strategy needs ticks
    subscribed_symbols = if requirements.ticks do
      Enum.reduce(symbols, [], fn sym, acc ->
        case DataCollector.TickerStream.subscribe(sym) do
          {:ok, count} ->
            Logger.info("Subscribed to ticker stream for #{sym} (subscribers: #{count})")
            Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{sym}")
            [sym | acc]

          {:error, reason} ->
            Logger.warning("Failed to subscribe to ticker stream for #{sym}: #{inspect(reason)}")
            acc
        end
      end)
    else
      Logger.info("Strategy does not require ticks, skipping ticker subscription")
      []
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
    {initial_action, strategy_state} = case strategy.init(strategy_config) do
      {:ok, state} -> {:noop, state}
      {:ok, state, action} -> {action, state}
    end

    state = %{
      account_id: account_id,
      setting_id: setting_id,
      api_key: api_key,
      secret_key: secret_key,
      strategy: strategy,
      strategy_state: strategy_state,
      strategy_config: strategy_config,
      symbol: symbol,
      symbols: symbols,                        # All required symbols
      subscribed_symbols: subscribed_symbols,  # Successfully subscribed symbols
      positions: %{},
      orders: %{},
      subscribed_to_ticks: length(subscribed_symbols) > 0,
      timer_refs: timer_refs
    }

    # Execute initial action if strategy returned one
    final_state = if initial_action != :noop do
      execute_action(initial_action, state)
    else
      state
    end

    {:ok, final_state}
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

            # Save order to database
            save_order_to_db(order, state.account_id)

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

  defp save_order_to_db(order, account_id) do
    attrs = %{
      order_id: to_string(order["orderId"]),
      client_order_id: order["clientOrderId"],
      symbol: order["symbol"],
      type: order["type"],
      side: order["side"],
      price: Decimal.new(order["price"] || "0"),
      quantity: Decimal.new(order["origQty"]),
      filled_qty: Decimal.new(order["executedQty"] || "0"),
      status: order["status"],
      time_in_force: order["timeInForce"],
      account_id: account_id
    }

    case SharedData.Trading.create_order(attrs) do
      {:ok, _db_order} ->
        Logger.info("Order #{order["orderId"]} saved to database")
      {:error, changeset} ->
        Logger.error("Failed to save order to database: #{inspect(changeset.errors)}")
    end
  end

  @impl true
  def handle_info({:ticker, market_data}, state) do
    # Migrate strategy state if needed (for hot code reloading)
    migrated_strategy_state = migrate_strategy_state(state.strategy_state)
    state = %{state | strategy_state: migrated_strategy_state}

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
      # Update order status in database
      update_order_in_db(execution)

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
    Logger.info("Trader terminating for symbols #{inspect(state.symbols)}, reason: #{inspect(reason)}")

    # Cancel open orders for Grid strategy on stop
    if state.strategy == TradingEngine.Strategies.Grid do
      cancel_open_orders_on_stop(state)
    end

    # Unsubscribe from ALL ticker streams
    Enum.each(state.subscribed_symbols || [], fn sym ->
      DataCollector.TickerStream.unsubscribe(sym)
    end)

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

  @doc false
  defp migrate_strategy_state(strategy_state) do
    strategy_state
    |> Map.put_new(:needs_initial_order, false)
    |> Map.put_new(:pending_order_id, nil)
  end

  @doc false
  defp update_order_in_db(execution) do
    order_id = to_string(execution["i"])
    status = execution["X"]
    filled_qty = execution["z"]

    case SharedData.Trading.update_order_status(
           order_id,
           status,
           filled_qty && Decimal.new(filled_qty)
         ) do
      {:ok, _order} ->
        Logger.debug("Order #{order_id} status updated to #{status}")

      {:error, :not_found} ->
        Logger.debug("Order #{order_id} not found in DB (may be external order)")

      {:error, reason} ->
        Logger.warning("Failed to update order #{order_id}: #{inspect(reason)}")
    end
  end

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
      {:reply, {:ok, order}, new_state} ->
        # Call on_order_placed if strategy implements it
        updated_strategy_state =
          if function_exported?(state.strategy, :on_order_placed, 2) do
            state.strategy.on_order_placed(order, new_state.strategy_state)
          else
            new_state.strategy_state
          end

        state_after_placed = %{new_state | strategy_state: updated_strategy_state}

        # If order was immediately filled, process it as execution
        if order["status"] == "FILLED" do
          Logger.info("Order #{order["orderId"]} was immediately filled, processing execution")
          execution = order_to_execution(order)
          {action, final_strategy_state} = state.strategy.on_execution(execution, state_after_placed.strategy_state)
          final_state = %{state_after_placed | strategy_state: final_strategy_state}
          execute_action(action, final_state)
        else
          state_after_placed
        end

      {:reply, {:error, _reason}, new_state} ->
        new_state
    end
  end

  # Convert order response to execution report format
  defp order_to_execution(order) do
    %{
      "i" => order["orderId"],
      "X" => order["status"],
      "S" => order["side"],
      "L" => order["price"],
      "z" => order["executedQty"] || order["origQty"],
      "s" => order["symbol"]
    }
  end

  # Check for existing chain state and open orders for recovery
  defp check_for_recovery(setting_id, api_key, secret_key, symbol) do
    # 1. Check for existing chain state in DB
    case SharedData.ChainStates.get_chain_state_by_setting(setting_id) do
      nil ->
        # No existing state, check for orphaned open orders
        check_orphaned_orders(api_key, secret_key, symbol)

      %{current_state: "completed"} ->
        # Chain completed, no recovery needed
        nil

      %{current_state: "error"} ->
        # Chain errored, no recovery needed
        nil

      chain_state ->
        # Active chain state found - check if pending order still exists
        verify_and_build_recovery(chain_state, api_key, secret_key, symbol)
    end
  end

  defp check_orphaned_orders(api_key, secret_key, symbol) do
    case BinanceClient.get_open_orders(api_key, secret_key, symbol) do
      {:ok, []} ->
        nil

      {:ok, open_orders} ->
        # Found orphaned open orders - return info for strategy to handle
        Logger.warning("Found #{length(open_orders)} orphaned open orders for #{symbol}")
        %{
          type: :orphaned_orders,
          orders: open_orders
        }

      {:error, _} ->
        nil
    end
  end

  defp verify_and_build_recovery(chain_state, api_key, secret_key, symbol) do
    pending_order_id = chain_state.pending_order_id

    # Check if pending order still exists on Binance
    open_orders = case BinanceClient.get_open_orders(api_key, secret_key, symbol) do
      {:ok, orders} -> orders
      {:error, _} -> []
    end

    pending_order = if pending_order_id do
      Enum.find(open_orders, fn o ->
        to_string(o["orderId"]) == pending_order_id
      end)
    end

    %{
      type: :chain_state,
      chain_state: chain_state,
      pending_order_exists: pending_order != nil,
      pending_order: pending_order,
      open_orders: open_orders
    }
  end

  @spec via_tuple(Types.account_id()) :: Types.genserver_name()
  defp via_tuple(account_id) do
    {:via, Registry, {TradingEngine.TraderRegistry, account_id}}
  end
end
