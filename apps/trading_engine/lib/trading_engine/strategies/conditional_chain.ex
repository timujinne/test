defmodule TradingEngine.Strategies.ConditionalChain do
  @moduledoc """
  Conditional Chain trading strategy.

  Executes a sequence of orders with conditional branching based on price movements.

  ## Chain Steps

  1. **Initial Step**: First order in the chain
  2. **Regular Steps**: Fixed price/quantity orders
  3. **Branch Steps**: Conditional branches with two paths:
     - `price_rises`: Execute if price moves up by threshold %
     - `price_falls`: Execute if price moves down by threshold %

  ## Example Configuration

  ```elixir
  %{
    "symbol" => "BTCUSDT",
    "initial_quantity" => "0.001",
    "branch_threshold_percent" => "1.0",  # ±1% default
    "steps" => [
      %{
        "type" => "initial",
        "side" => "BUY",
        "price" => "50000.00",
        "quantity" => "0.001"
      },
      %{
        "type" => "step",
        "side" => "SELL",
        "price" => "51000.00",
        "quantity" => "0.001"
      },
      %{
        "type" => "branch",
        "price_rises" => %{
          "side" => "SELL",
          "price" => "52000.00",
          "quantity" => "0.001"
        },
        "price_falls" => %{
          "side" => "BUY",
          "price" => "49000.00",
          "quantity" => "0.001"
        }
      }
    ]
  }
  ```

  ## State Lifecycle

  - `:idle` - Initial state, no chain started
  - `:awaiting_initial` - Initial order placed, waiting for fill
  - `:awaiting_step` - Regular step order placed, waiting for fill
  - `:awaiting_branch` - Previous step filled, monitoring price for branch condition
  - `:completed` - All steps executed successfully
  - `:error` - Error occurred during execution
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def requirements(_config) do
    %{
      ticks: true,        # Need ticks for branch condition evaluation
      timers: [],
      executions: true    # Need executions to advance chain
    }
  end

  @impl true
  def required_symbols(config) do
    # Extract all unique symbols from steps (supports multi-symbol chains)
    config["symbols"] || extract_symbols_from_steps(config["steps"] || []) || [config["symbol"]]
  end

  defp extract_symbols_from_steps(steps) do
    symbols = steps
    |> Enum.flat_map(fn step ->
      cond do
        step["symbol"] -> [step["symbol"]]
        step["type"] == "branch" ->
          [
            get_in(step, ["price_rises", "symbol"]),
            get_in(step, ["price_falls", "symbol"])
          ]
        true -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()

    if symbols == [], do: nil, else: symbols
  end

  @impl true
  def init(config) do
    # Check for recovery state from Trader
    recovery = config["_recovery"]

    if recovery && recovery.type == :chain_state do
      init_from_recovery(config, recovery)
    else
      init_fresh(config, recovery)
    end
  end

  # Initialize from saved chain state (recovery after restart)
  defp init_from_recovery(config, recovery) do
    chain_state = recovery.chain_state
    steps = config["steps"] || []
    symbols = config["symbols"] || extract_symbols_from_steps(steps) || [config["symbol"]]

    # Determine current symbol based on step index
    current_step = Enum.at(steps, chain_state.current_step_index || 0)
    current_symbol = (current_step && current_step["symbol"]) || config["symbol"] || List.first(symbols)

    state = %{
      symbols: symbols,
      current_symbol: current_symbol,
      symbol: config["symbol"],
      setting_id: chain_state.setting_id,

      chain_id: chain_state.chain_id,
      steps: steps,
      current_step_index: chain_state.current_step_index || 0,
      current_state: String.to_existing_atom(chain_state.current_state),
      pending_order_id: chain_state.pending_order_id,
      reference_price: chain_state.reference_price,
      last_fill_price: chain_state.last_fill_price,
      initial_fill_price: chain_state.initial_fill_price,
      initial_quantity: chain_state.initial_quantity || to_decimal(config["initial_quantity"], "0"),
      current_quantity: chain_state.current_quantity || Decimal.new("0"),
      branch_threshold_percent: to_decimal(config["branch_threshold_percent"], "1.0"),
      state_history: [],
      needs_initial_order: false,  # Don't place new order - recovering
      last_sell_proceeds: nil,
      db_chain_state_id: chain_state.id
    }

    # Check if pending order still exists
    if recovery.pending_order_exists do
      Logger.info("ConditionalChain[#{chain_state.chain_id}]: Recovered - pending order ##{chain_state.pending_order_id} still exists")
      {:ok, state}
    else
      # Pending order doesn't exist - might have been filled or cancelled
      Logger.warning("ConditionalChain[#{chain_state.chain_id}]: Recovered but pending order ##{chain_state.pending_order_id} not found on Binance")
      # Mark as needing investigation - don't auto-place new orders
      {:ok, %{state | current_state: :error}}
    end
  end

  # Initialize fresh (no recovery needed)
  defp init_fresh(config, recovery) do
    steps = config["steps"] || []
    symbols = config["symbols"] || extract_symbols_from_steps(steps) || [config["symbol"]]
    first_step = List.first(steps)
    initial_symbol = (first_step && first_step["symbol"]) || config["symbol"] || List.first(symbols)

    # Check for orphaned orders
    has_orphaned = recovery && recovery.type == :orphaned_orders && length(recovery.orders) > 0

    if has_orphaned do
      Logger.warning("ConditionalChain: Found #{length(recovery.orders)} orphaned orders - starting in error state to prevent duplicates")
      chain_id = generate_chain_id()

      state = %{
        symbols: symbols,
        current_symbol: initial_symbol,
        symbol: config["symbol"],
        setting_id: config["setting_id"],
        chain_id: chain_id,
        steps: steps,
        current_step_index: 0,
        current_state: :error,  # Error state - needs manual intervention
        pending_order_id: nil,
        reference_price: nil,
        last_fill_price: nil,
        initial_fill_price: nil,
        initial_quantity: to_decimal(config["initial_quantity"], "0"),
        current_quantity: Decimal.new("0"),
        branch_threshold_percent: to_decimal(config["branch_threshold_percent"], "1.0"),
        state_history: [{:error, "Orphaned orders found: #{inspect(Enum.map(recovery.orders, & &1["orderId"]))}"}],
        needs_initial_order: false,
        last_sell_proceeds: nil,
        orphaned_orders: recovery.orders
      }

      {:ok, state}
    else
      # Normal fresh start
      chain_id = generate_chain_id()

      state = %{
        symbols: symbols,
        current_symbol: initial_symbol,
        symbol: config["symbol"],
        setting_id: config["setting_id"],
        chain_id: chain_id,
        steps: steps,
        current_step_index: 0,
        current_state: :idle,
        pending_order_id: nil,
        reference_price: nil,
        last_fill_price: nil,
        initial_fill_price: nil,
        initial_quantity: to_decimal(config["initial_quantity"], "0"),
        current_quantity: Decimal.new("0"),
        branch_threshold_percent: to_decimal(config["branch_threshold_percent"], "1.0"),
        state_history: [],
        needs_initial_order: length(steps) > 0,
        last_sell_proceeds: nil
      }

      Logger.info("ConditionalChain[#{chain_id}]: Fresh start for symbols #{inspect(symbols)}, #{length(steps)} steps")

      {:ok, state}
    end
  end

  @impl true
  def on_tick(market_data, state) do
    tick_symbol = market_data["s"]

    # Filter: only process ticks for current active symbol
    if tick_symbol != state.current_symbol do
      {:noop, state}
    else
      current_price = Decimal.new(market_data["c"])

      cond do
        # Place initial order on first tick
        state.needs_initial_order && state.current_state == :idle ->
          case place_initial_order(state) do
            {:ok, order_params, new_state} ->
              Logger.info("ConditionalChain[#{state.chain_id}]: Placing initial order on first tick")
              new_state = %{new_state | needs_initial_order: false}
              {{:place_order, order_params}, new_state}

            {:error, reason} ->
              Logger.error("ConditionalChain[#{state.chain_id}]: Failed to place initial order: #{inspect(reason)}")
              {:noop, %{state | current_state: :error, needs_initial_order: false}}
          end

        # Evaluate branch condition when waiting
        state.current_state == :awaiting_branch ->
          action = evaluate_branch_condition(current_price, state)
          {action, state}

        true ->
          {:noop, state}
      end
    end
  end

  @impl true
  def on_execution(execution, state) do
    case execution["X"] do
      # Only process FILLED orders (ignore PARTIALLY_FILLED)
      "FILLED" ->
        order_id = to_string(execution["i"])

        if order_id == state.pending_order_id do
          handle_order_filled(execution, state)
        else
          Logger.debug("ConditionalChain[#{state.chain_id}]: Ignoring execution for non-pending order #{order_id}")
          {:noop, state}
        end

      "PARTIALLY_FILLED" ->
        Logger.debug("ConditionalChain[#{state.chain_id}]: Ignoring partial fill")
        {:noop, state}

      _ ->
        {:noop, state}
    end
  end

  @impl true
  def on_order_placed(order, state) do
    %{state | pending_order_id: to_string(order["orderId"])}
  end

  # Private Functions

  defp place_initial_order(state) do
    step = Enum.at(state.steps, 0)

    if step && step["type"] == "initial" do
      order_params = build_order_params(step, state)
      new_state = %{state |
        current_state: :awaiting_initial,
        state_history: add_to_history(state, :awaiting_initial, "Placed initial order")
      }
      # Persist state after placing initial order
      new_state = persist_state(new_state)
      {:ok, order_params, new_state}
    else
      {:error, "First step must be of type 'initial'"}
    end
  end

  defp handle_order_filled(execution, state) do
    side = execution["S"]
    fill_price = Decimal.new(execution["L"])
    fill_qty = Decimal.new(execution["z"])  # Cumulative filled quantity
    symbol = execution["s"]

    Logger.info("ConditionalChain[#{state.chain_id}]: Order filled - #{side} #{fill_qty} #{symbol} @ #{fill_price}")

    # Calculate proceeds if SELL (for "use_profit" feature)
    last_sell_proceeds = if side == "SELL" do
      Decimal.mult(fill_price, fill_qty)
    else
      state.last_sell_proceeds
    end

    # Update state with fill information
    new_state = case state.current_state do
      :awaiting_initial ->
        %{state |
          initial_fill_price: fill_price,
          last_fill_price: fill_price,
          current_quantity: fill_qty,
          pending_order_id: nil,
          last_sell_proceeds: last_sell_proceeds
        }

      _ ->
        # Update quantity based on side
        updated_qty = case side do
          "BUY" -> Decimal.add(state.current_quantity, fill_qty)
          "SELL" -> Decimal.sub(state.current_quantity, fill_qty)
        end

        %{state |
          last_fill_price: fill_price,
          current_quantity: updated_qty,
          pending_order_id: nil,
          last_sell_proceeds: last_sell_proceeds
        }
    end

    # Advance to next step
    advance_chain(new_state)
  end

  defp advance_chain(state) do
    next_index = state.current_step_index + 1

    if next_index >= length(state.steps) do
      # Chain completed
      Logger.info("ConditionalChain[#{state.chain_id}]: Chain completed successfully")
      new_state = %{state |
        current_state: :completed,
        current_symbol: nil,
        state_history: add_to_history(state, :completed, "Chain completed")
      }
      # Persist final state
      new_state = persist_state(new_state)
      {:noop, new_state}
    else
      next_step = Enum.at(state.steps, next_index)
      # Get symbol for next step (multi-symbol support)
      next_symbol = next_step["symbol"] || state.current_symbol || state.symbol

      # Log symbol transition if changed
      if next_symbol != state.current_symbol do
        Logger.info("ConditionalChain[#{state.chain_id}]: Switching symbol from #{state.current_symbol} to #{next_symbol}")
      end

      case next_step["type"] do
        "step" ->
          # Regular step - place order immediately
          place_step_order(next_step, next_index, %{state | current_symbol: next_symbol})

        "branch" ->
          # Branch step - wait for price condition
          Logger.info("ConditionalChain[#{state.chain_id}]: Entering branch step, monitoring price movements for #{next_symbol}")
          new_state = %{state |
            current_step_index: next_index,
            current_state: :awaiting_branch,
            current_symbol: next_symbol,
            reference_price: state.last_fill_price,
            state_history: add_to_history(state, :awaiting_branch, "Waiting for branch condition")
          }
          # Persist state when entering branch
          new_state = persist_state(new_state)
          {:noop, new_state}

        unknown_type ->
          Logger.error("ConditionalChain[#{state.chain_id}]: Unknown step type: #{unknown_type}")
          new_state = %{state |
            current_state: :error,
            state_history: add_to_history(state, :error, "Unknown step type: #{unknown_type}")
          }
          # Persist error state
          new_state = persist_state(new_state)
          {:noop, new_state}
      end
    end
  end

  defp place_step_order(step, step_index, state) do
    order_params = build_order_params(step, state)

    Logger.info("ConditionalChain[#{state.chain_id}]: Placing step #{step_index} order - #{step["side"]} @ #{step["price"]}")

    new_state = %{state |
      current_step_index: step_index,
      current_state: :awaiting_step,
      state_history: add_to_history(state, :awaiting_step, "Placed step #{step_index} order")
    }
    # Persist state after placing step order
    new_state = persist_state(new_state)

    {{:place_order, order_params}, new_state}
  end

  defp evaluate_branch_condition(current_price, state) do
    if state.reference_price == nil do
      Logger.warning("ConditionalChain[#{state.chain_id}]: No reference price for branch evaluation")
      :noop
    else
      threshold_decimal = Decimal.div(state.branch_threshold_percent, 100)
      upper_threshold = Decimal.mult(state.reference_price, Decimal.add(1, threshold_decimal))
      lower_threshold = Decimal.mult(state.reference_price, Decimal.sub(1, threshold_decimal))

      cond do
        # Price rose above threshold
        Decimal.compare(current_price, upper_threshold) == :gt ->
          Logger.info("ConditionalChain[#{state.chain_id}]: Price rose above threshold (#{current_price} > #{upper_threshold}), taking price_rises branch")
          execute_branch(state, "price_rises")

        # Price fell below threshold
        Decimal.compare(current_price, lower_threshold) == :lt ->
          Logger.info("ConditionalChain[#{state.chain_id}]: Price fell below threshold (#{current_price} < #{lower_threshold}), taking price_falls branch")
          execute_branch(state, "price_falls")

        true ->
          # Still within threshold range
          :noop
      end
    end
  end

  defp execute_branch(state, branch_path) do
    current_step = Enum.at(state.steps, state.current_step_index)
    branch_config = current_step[branch_path]

    if branch_config do
      order_params = build_order_params(branch_config, state)

      new_state = %{state |
        current_state: :awaiting_step,
        reference_price: nil,
        state_history: add_to_history(state, :awaiting_step, "Executing #{branch_path} branch")
      }

      # Persist state before placing order
      new_state = persist_state(new_state)

      {{:place_order, order_params}, new_state}
    else
      Logger.error("ConditionalChain[#{state.chain_id}]: Branch path #{branch_path} not configured")
      :noop
    end
  end

  defp build_order_params(step_config, state) do
    # Use step-specific symbol, fallback to current_symbol or legacy symbol
    symbol = step_config["symbol"] || state.current_symbol || state.symbol
    {price_precision, qty_precision} = get_symbol_precision(symbol)

    price = to_decimal(step_config["price"], "0") |> Decimal.round(price_precision)

    # Handle "use_profit" quantity - calculate from previous sell proceeds
    quantity = case step_config["quantity"] do
      "use_profit" ->
        calculate_profit_quantity(state, price, qty_precision)
      qty ->
        to_decimal(qty, state.initial_quantity) |> Decimal.round(qty_precision)
    end

    %{
      symbol: symbol,
      side: step_config["side"],
      type: "LIMIT",
      price: price,
      quantity: quantity,
      timeInForce: "GTC"
    }
  end

  # Calculate quantity from previous sell proceeds
  defp calculate_profit_quantity(state, target_price, qty_precision) do
    if state.last_sell_proceeds && Decimal.compare(target_price, 0) == :gt do
      # proceeds (USDT) / target_price = quantity
      Decimal.div(state.last_sell_proceeds, target_price)
      |> Decimal.round(qty_precision)
    else
      Logger.warning("ConditionalChain[#{state.chain_id}]: No sell proceeds for use_profit, using initial_quantity")
      state.initial_quantity
    end
  end

  defp generate_chain_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp add_to_history(state, new_state, message) do
    entry = %{
      timestamp: DateTime.utc_now(),
      state: new_state,
      message: message,
      step_index: state.current_step_index
    }

    [entry | state.state_history]
    |> Enum.take(50)  # Keep last 50 entries
  end

  # Convert various types to Decimal safely
  defp to_decimal(nil, default), do: to_decimal(default, "0")
  defp to_decimal(value, _default) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(%Decimal{} = value, _default), do: value

  # Symbol precision for price and quantity
  defp get_symbol_precision(symbol) do
    TradingEngine.SymbolInfo.get_precision(symbol)
  end

  # Persist state to database for recovery after restart
  defp persist_state(state) do
    # Only persist if we have a setting_id
    setting_id = state[:setting_id]

    if setting_id do
      attrs = %{
        chain_id: state.chain_id,
        setting_id: setting_id,
        current_step_index: state.current_step_index,
        current_state: to_string(state.current_state),
        pending_order_id: state.pending_order_id,
        reference_price: state.reference_price,
        last_fill_price: state.last_fill_price,
        initial_fill_price: state.initial_fill_price,
        initial_quantity: state.initial_quantity,
        current_quantity: state.current_quantity,
        started_at: DateTime.utc_now()
      }

      # Add completed_at if chain is done
      attrs = if state.current_state in [:completed, :error] do
        Map.put(attrs, :completed_at, DateTime.utc_now())
      else
        attrs
      end

      case state[:db_chain_state_id] do
        nil ->
          # Create new chain state record
          case SharedData.ChainStates.create_chain_state(attrs) do
            {:ok, chain_state} ->
              Logger.debug("ConditionalChain[#{state.chain_id}]: State persisted to DB (id: #{chain_state.id})")
              %{state | db_chain_state_id: chain_state.id}

            {:error, changeset} ->
              Logger.warning("ConditionalChain[#{state.chain_id}]: Failed to persist state: #{inspect(changeset.errors)}")
              state
          end

        db_id ->
          # Update existing record
          case SharedData.ChainStates.get_chain_state(db_id) do
            nil ->
              Logger.warning("ConditionalChain[#{state.chain_id}]: DB record not found, creating new")
              case SharedData.ChainStates.create_chain_state(attrs) do
                {:ok, chain_state} -> %{state | db_chain_state_id: chain_state.id}
                {:error, _} -> state
              end

            existing ->
              case SharedData.ChainStates.update_chain_state(existing, attrs) do
                {:ok, _} ->
                  Logger.debug("ConditionalChain[#{state.chain_id}]: State updated in DB")
                  state

                {:error, changeset} ->
                  Logger.warning("ConditionalChain[#{state.chain_id}]: Failed to update state: #{inspect(changeset.errors)}")
                  state
              end
          end
      end
    else
      Logger.debug("ConditionalChain[#{state.chain_id}]: No setting_id, skipping DB persistence")
      state
    end
  end
end
