defmodule TradingEngine.SharedPositionTracker do
  @moduledoc """
  Tracks aggregated positions across all strategies for each account.

  Maintains a unified view of positions by:
  - Tracking fills from all strategies
  - Calculating average entry prices
  - Computing unrealized P&L
  - Supporting hedged and netted position views
  """
  use GenServer
  require Logger

  @order_updates_topic "order_updates"
  @position_updates_topic "position_updates"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get position for account/symbol.
  """
  @spec get_position(String.t(), String.t()) :: map()
  def get_position(account_id, symbol) do
    GenServer.call(__MODULE__, {:get_position, account_id, symbol})
  end

  @doc """
  Get all positions for an account.
  """
  @spec get_account_positions(String.t()) :: [map()]
  def get_account_positions(account_id) do
    GenServer.call(__MODULE__, {:get_account_positions, account_id})
  end

  @doc """
  Get all positions across all accounts.
  """
  @spec get_all_positions() :: map()
  def get_all_positions do
    GenServer.call(__MODULE__, :get_all_positions)
  end

  @doc """
  Update position from a trade execution.
  """
  @spec record_fill(String.t(), map()) :: :ok
  def record_fill(account_id, fill) do
    GenServer.cast(__MODULE__, {:record_fill, account_id, fill})
  end

  @doc """
  Update current market price for P&L calculation.
  """
  @spec update_market_price(String.t(), Decimal.t() | String.t()) :: :ok
  def update_market_price(symbol, price) do
    GenServer.cast(__MODULE__, {:update_price, symbol, price})
  end

  @doc """
  Close position (reset to zero).
  """
  @spec close_position(String.t(), String.t()) :: :ok
  def close_position(account_id, symbol) do
    GenServer.cast(__MODULE__, {:close_position, account_id, symbol})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, @order_updates_topic)

    state = %{
      positions: %{},
      market_prices: %{},
      subscribed_symbols: MapSet.new()
    }

    Logger.info("SharedPositionTracker started")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_position, account_id, symbol}, _from, state) do
    position =
      state.positions
      |> get_in([account_id, symbol])
      |> position_or_default(account_id, symbol)
      |> add_unrealized_pnl(state.market_prices)

    {:reply, position, state}
  end

  @impl true
  def handle_call({:get_account_positions, account_id}, _from, state) do
    positions =
      state.positions
      |> Map.get(account_id, %{})
      |> Enum.map(fn {_symbol, pos} -> add_unrealized_pnl(pos, state.market_prices) end)
      |> Enum.filter(fn pos -> Decimal.compare(pos.net_quantity, Decimal.new(0)) != :eq end)

    {:reply, positions, state}
  end

  @impl true
  def handle_call(:get_all_positions, _from, state) do
    all_positions =
      state.positions
      |> Enum.flat_map(fn {account_id, symbols} ->
        Enum.map(symbols, fn {symbol, pos} ->
          {account_id, symbol, add_unrealized_pnl(pos, state.market_prices)}
        end)
      end)
      |> Enum.filter(fn {_, _, pos} ->
        Decimal.compare(pos.net_quantity, Decimal.new(0)) != :eq
      end)

    {:reply, all_positions, state}
  end

  @impl true
  def handle_cast({:record_fill, account_id, fill}, state) do
    symbol = fill[:symbol] || fill["symbol"] || fill["s"]
    side = fill[:side] || fill["side"] || fill["S"]
    quantity = parse_decimal(fill[:quantity] || fill["quantity"] || fill["q"])
    price = parse_decimal(fill[:price] || fill["price"] || fill["p"])

    new_state = update_position(state, account_id, symbol, side, quantity, price)

    # Broadcast position update
    position = get_in(new_state.positions, [account_id, symbol])

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      @position_updates_topic,
      {:position_updated, account_id, symbol, position}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_price, symbol, price}, state) do
    new_prices = Map.put(state.market_prices, symbol, parse_decimal(price))
    {:noreply, %{state | market_prices: new_prices}}
  end

  @impl true
  def handle_cast({:close_position, account_id, symbol}, state) do
    new_positions =
      state.positions
      |> put_in([Access.key(account_id, %{}), symbol], default_position(account_id, symbol))

    Logger.info("Closed position for #{account_id}/#{symbol}")
    {:noreply, %{state | positions: new_positions}}
  end

  @impl true
  def handle_info({:execution_report, report}, state) do
    # Handle execution reports from WebSocket
    if report["x"] == "TRADE" or report["X"] == "FILLED" or report["X"] == "PARTIALLY_FILLED" do
      account_id = report["account_id"] || "unknown"
      symbol = report["s"]
      side = report["S"]
      quantity = parse_decimal(report["l"])
      price = parse_decimal(report["L"])

      # Subscribe to market data if needed
      new_subscribed =
        if MapSet.member?(state.subscribed_symbols, symbol) do
          state.subscribed_symbols
        else
          Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")
          MapSet.put(state.subscribed_symbols, symbol)
        end

      new_state =
        state
        |> update_position(account_id, symbol, side, quantity, price)
        |> Map.put(:subscribed_symbols, new_subscribed)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ticker, market_data}, state) do
    symbol = market_data["s"]
    price = parse_decimal(market_data["c"])
    new_prices = Map.put(state.market_prices, symbol, price)
    {:noreply, %{state | market_prices: new_prices}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp update_position(state, account_id, symbol, side, quantity, price) do
    current_position =
      state.positions
      |> get_in([account_id, symbol])
      |> position_or_default(account_id, symbol)

    # Calculate new position
    {new_quantity, new_avg_price, realized_pnl} =
      calculate_new_position(current_position, side, quantity, price)

    updated_position = %{
      current_position
      | net_quantity: new_quantity,
        avg_entry_price: new_avg_price,
        realized_pnl: Decimal.add(current_position.realized_pnl, realized_pnl),
        last_fill_at: DateTime.utc_now(),
        total_bought: update_total(current_position.total_bought, side, "BUY", quantity),
        total_sold: update_total(current_position.total_sold, side, "SELL", quantity),
        fill_count: current_position.fill_count + 1
    }

    # Ensure nested map exists
    account_positions = Map.get(state.positions, account_id, %{})
    new_account_positions = Map.put(account_positions, symbol, updated_position)

    %{state | positions: Map.put(state.positions, account_id, new_account_positions)}
  end

  defp calculate_new_position(position, side, quantity, price) do
    current_qty = position.net_quantity
    current_avg = position.avg_entry_price

    # BUY increases position, SELL decreases
    signed_qty =
      if side == "BUY" do
        quantity
      else
        Decimal.negate(quantity)
      end

    new_qty = Decimal.add(current_qty, signed_qty)

    cond do
      # Opening or adding to position in same direction
      same_direction?(current_qty, signed_qty) ->
        # Weighted average price
        if Decimal.compare(Decimal.add(Decimal.abs(current_qty), quantity), Decimal.new(0)) == :eq do
          {new_qty, Decimal.new(0), Decimal.new(0)}
        else
          total_cost =
            Decimal.add(
              Decimal.mult(Decimal.abs(current_qty), current_avg),
              Decimal.mult(quantity, price)
            )

          new_avg = Decimal.div(total_cost, Decimal.add(Decimal.abs(current_qty), quantity))
          {new_qty, new_avg, Decimal.new(0)}
        end

      # Reducing position
      Decimal.compare(Decimal.abs(new_qty), Decimal.new(0)) != :eq and
          not position_flipped?(current_qty, new_qty) ->
        # Realized P&L for reduced amount
        price_diff = Decimal.sub(price, current_avg)

        realized =
          if Decimal.compare(current_qty, Decimal.new(0)) == :gt do
            # Was long, selling
            Decimal.mult(price_diff, quantity)
          else
            # Was short, buying
            Decimal.negate(Decimal.mult(price_diff, quantity))
          end

        {new_qty, current_avg, realized}

      # Position closed exactly
      Decimal.compare(new_qty, Decimal.new(0)) == :eq ->
        price_diff = Decimal.sub(price, current_avg)

        realized =
          if Decimal.compare(current_qty, Decimal.new(0)) == :gt do
            Decimal.mult(price_diff, Decimal.abs(current_qty))
          else
            Decimal.negate(Decimal.mult(price_diff, Decimal.abs(current_qty)))
          end

        {Decimal.new(0), Decimal.new(0), realized}

      # Position flipped (long -> short or vice versa)
      true ->
        # First, realize P&L on closed portion
        closed_qty = Decimal.abs(current_qty)
        price_diff = Decimal.sub(price, current_avg)

        realized =
          if Decimal.compare(current_qty, Decimal.new(0)) == :gt do
            Decimal.mult(price_diff, closed_qty)
          else
            Decimal.negate(Decimal.mult(price_diff, closed_qty))
          end

        # New position starts at current price
        {new_qty, price, realized}
    end
  end

  defp same_direction?(current_qty, signed_qty) do
    (Decimal.compare(current_qty, Decimal.new(0)) != :lt and
       Decimal.compare(signed_qty, Decimal.new(0)) != :lt) or
      (Decimal.compare(current_qty, Decimal.new(0)) != :gt and
         Decimal.compare(signed_qty, Decimal.new(0)) != :gt)
  end

  defp position_flipped?(current_qty, new_qty) do
    (Decimal.compare(current_qty, Decimal.new(0)) == :gt and
       Decimal.compare(new_qty, Decimal.new(0)) == :lt) or
      (Decimal.compare(current_qty, Decimal.new(0)) == :lt and
         Decimal.compare(new_qty, Decimal.new(0)) == :gt)
  end

  defp update_total(current, side, target_side, quantity) do
    if side == target_side do
      Decimal.add(current, quantity)
    else
      current
    end
  end

  defp add_unrealized_pnl(position, market_prices) do
    market_price = Map.get(market_prices, position.symbol, Decimal.new(0))

    unrealized =
      if Decimal.compare(position.net_quantity, Decimal.new(0)) != :eq and
           Decimal.compare(market_price, Decimal.new(0)) != :eq do
        price_diff = Decimal.sub(market_price, position.avg_entry_price)
        Decimal.mult(price_diff, position.net_quantity)
      else
        Decimal.new(0)
      end

    Map.put(position, :unrealized_pnl, unrealized)
  end

  defp position_or_default(nil, account_id, symbol), do: default_position(account_id, symbol)
  defp position_or_default(position, _account_id, _symbol), do: position

  defp default_position(account_id, symbol) do
    %{
      account_id: account_id,
      symbol: symbol,
      net_quantity: Decimal.new(0),
      avg_entry_price: Decimal.new(0),
      realized_pnl: Decimal.new(0),
      unrealized_pnl: Decimal.new(0),
      total_bought: Decimal.new(0),
      total_sold: Decimal.new(0),
      fill_count: 0,
      last_fill_at: nil
    }
  end

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(s) when is_binary(s), do: Decimal.new(s)
  defp parse_decimal(n) when is_number(n), do: Decimal.new("#{n}")
end
