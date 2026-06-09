defmodule TradingEngine.Strategies.Grid do
  @moduledoc """
  Grid trading strategy.

  Creates a grid of buy and sell orders at different price levels.
  Automatically rebalances when orders are filled.
  """
  @behaviour TradingEngine.Strategy

  require Logger

  @impl true
  def requirements(_config) do
    # Grid strategy needs ticks to get initial price and monitor the market
    %{
      ticks: true,
      timers: [],
      executions: true
    }
  end

  @impl true
  def required_symbols(config) do
    [config["symbol"]]
  end

  @impl true
  def init(config) do
    # Support both naming conventions from UI
    amount = config["amount_per_grid"] || config["quantity_per_grid"]
    recovery = config["_recovery"]

    state = %{
      symbol: config["symbol"],
      grid_levels: to_integer(config["grid_levels"], 5),
      grid_spacing: to_decimal(config["grid_spacing"], "0.005"),
      amount_per_grid: to_decimal(amount, "50"),
      base_price: nil,
      active_orders: [],
      skip_initial_grid: false
    }

    # Check for existing open orders (recovery after restart)
    state =
      if recovery && recovery.type == :orphaned_orders && length(recovery.orders) > 0 do
        existing_orders = recovery.orders

        Logger.warning(
          "Grid: Found #{length(existing_orders)} existing orders on Binance - using them instead of creating new grid"
        )

        # Calculate approximate base price from existing orders
        prices =
          Enum.map(existing_orders, fn o ->
            Decimal.new(o["price"])
          end)

        avg_price =
          Decimal.div(Enum.reduce(prices, Decimal.new(0), &Decimal.add/2), length(prices))

        # Mark active orders from Binance
        active_orders =
          Enum.map(existing_orders, fn o ->
            %{order_id: o["orderId"], price: o["price"], side: o["side"]}
          end)

        %{
          state
          | base_price: avg_price,
            active_orders: active_orders,
            # Don't create new grid
            skip_initial_grid: true
        }
      else
        state
      end

    Logger.info(
      "Grid: Initialized with #{state.grid_levels} levels, spacing #{state.grid_spacing}, amount #{state.amount_per_grid} per grid"
    )

    {:ok, state}
  end

  defp to_integer(nil, default), do: default
  defp to_integer(value, _default) when is_integer(value), do: value
  defp to_integer(value, _default) when is_float(value), do: trunc(value)

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  # Convert various types to Decimal safely
  defp to_decimal(nil, default), do: Decimal.new(default)
  defp to_decimal(value, _default) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value, _default) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(%Decimal{} = value, _default), do: value

  @impl true
  def on_tick(market_data, state) do
    current_price = Decimal.new(market_data["c"])

    action =
      cond do
        # Skip creating grid if we recovered existing orders
        state.skip_initial_grid ->
          Logger.info("Grid: Skipping grid creation - using recovered orders")
          :noop

        # Initialize grid based on current price (first tick only)
        state.base_price == nil ->
          Logger.info("Grid: Initializing grid at #{current_price}")
          {:place_order, create_grid_orders(current_price, state)}

        true ->
          :noop
      end

    # Clear skip flag after first tick
    new_state = %{state | base_price: current_price, skip_initial_grid: false}
    {action, new_state}
  end

  @impl true
  def on_execution(execution, state) do
    case execution["x"] do
      "TRADE" ->
        order_id = execution["i"]
        side = execution["S"]
        price = Decimal.new(execution["L"])

        Logger.info("Grid: Order #{order_id} filled (#{side}) at #{price}")

        # Remove filled order from active orders
        new_active_orders =
          Enum.reject(state.active_orders, fn o ->
            o.order_id == order_id
          end)

        # Place opposite order at the next grid level
        {price_precision, qty_precision} = get_symbol_precision(state.symbol)

        opposite_order =
          case side do
            "BUY" ->
              # After buy, place sell order above
              sell_price =
                Decimal.mult(price, Decimal.add(1, state.grid_spacing))
                |> Decimal.round(price_precision)

              qty = Decimal.div(state.amount_per_grid, sell_price) |> Decimal.round(qty_precision)

              %{
                symbol: state.symbol,
                side: "SELL",
                type: "LIMIT",
                price: sell_price,
                quantity: qty,
                timeInForce: "GTC"
              }

            "SELL" ->
              # After sell, place buy order below
              buy_price =
                Decimal.mult(price, Decimal.sub(1, state.grid_spacing))
                |> Decimal.round(price_precision)

              qty = Decimal.div(state.amount_per_grid, buy_price) |> Decimal.round(qty_precision)

              %{
                symbol: state.symbol,
                side: "BUY",
                type: "LIMIT",
                price: buy_price,
                quantity: qty,
                timeInForce: "GTC"
              }
          end

        new_state = %{state | active_orders: new_active_orders}
        {{:place_order, opposite_order}, new_state}

      _ ->
        {:noop, state}
    end
  end

  # Private functions

  defp create_grid_orders(base_price, state) do
    {price_precision, qty_precision} = get_symbol_precision(state.symbol)

    buy_orders =
      for i <- 1..state.grid_levels do
        price =
          Decimal.mult(
            base_price,
            Decimal.sub(1, Decimal.mult(state.grid_spacing, i))
          )
          |> Decimal.round(price_precision)

        # Calculate quantity: amount_per_grid (USDT) / price = quantity of coins
        quantity = Decimal.div(state.amount_per_grid, price) |> Decimal.round(qty_precision)

        %{
          symbol: state.symbol,
          side: "BUY",
          type: "LIMIT",
          price: price,
          quantity: quantity,
          timeInForce: "GTC"
        }
      end

    sell_orders =
      for i <- 1..state.grid_levels do
        price =
          Decimal.mult(
            base_price,
            Decimal.add(1, Decimal.mult(state.grid_spacing, i))
          )
          |> Decimal.round(price_precision)

        # Calculate quantity: amount_per_grid (USDT) / price = quantity of coins
        quantity = Decimal.div(state.amount_per_grid, price) |> Decimal.round(qty_precision)

        %{
          symbol: state.symbol,
          side: "SELL",
          type: "LIMIT",
          price: price,
          quantity: quantity,
          timeInForce: "GTC"
        }
      end

    Logger.info(
      "Grid: Creating #{length(buy_orders)} buy orders and #{length(sell_orders)} sell orders"
    )

    buy_orders ++ sell_orders
  end

  # Symbol precision for price and quantity
  # TODO: Fetch from Binance exchangeInfo API
  defp get_symbol_precision(symbol) do
    case symbol do
      # price: 0.01, qty: 0.00001
      "BTCUSDT" -> {2, 5}
      # price: 0.01, qty: 0.0001
      "ETHUSDT" -> {2, 4}
      # price: 0.00001, qty: 1
      "DOGEUSDT" -> {5, 0}
      # price: 0.01, qty: 0.01
      "SOLUSDT" -> {2, 2}
      # price: 0.001, qty: 0.01
      "DOTUSDT" -> {3, 2}
      # default: 5 decimals price, 2 decimals qty
      _ -> {5, 2}
    end
  end
end
