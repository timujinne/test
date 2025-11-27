defmodule TradingEngine.AccountCoordinator do
  @moduledoc """
  Coordinates multiple strategies running on a single account.

  Responsibilities:
  - Tracks all active strategies per account
  - Aggregates positions across strategies
  - Enforces account-level risk limits
  - Handles account-level stop conditions (e.g., max daily loss)
  - Resolves conflicts between strategies (e.g., opposing signals)
  """
  use GenServer
  require Logger

  alias TradingEngine.SharedPositionTracker

  @topic "strategy_updates"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get account summary including all strategies and aggregated position.
  """
  @spec get_account_summary(String.t()) :: map()
  def get_account_summary(account_id) do
    GenServer.call(__MODULE__, {:get_summary, account_id})
  end

  @doc """
  Check if account can accept a new order (risk limits check).
  """
  @spec can_place_order?(String.t(), map()) :: {:ok, :allowed} | {:error, atom()}
  def can_place_order?(account_id, order_params) do
    GenServer.call(__MODULE__, {:can_place_order, account_id, order_params})
  end

  @doc """
  Get all active strategies for an account.
  """
  @spec get_account_strategies(String.t()) :: [map()]
  def get_account_strategies(account_id) do
    GenServer.call(__MODULE__, {:get_strategies, account_id})
  end

  @doc """
  Get aggregated position for a symbol across all strategies.
  """
  @spec get_aggregated_position(String.t(), String.t()) :: map()
  def get_aggregated_position(account_id, symbol) do
    GenServer.call(__MODULE__, {:get_position, account_id, symbol})
  end

  @doc """
  List all accounts with active strategies.
  """
  @spec list_active_accounts() :: [String.t()]
  def list_active_accounts do
    GenServer.call(__MODULE__, :list_accounts)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(BinanceSystem.PubSub, @topic)

    state = %{
      accounts: %{},
      account_limits: %{}
    }

    Logger.info("AccountCoordinator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:get_summary, account_id}, _from, state) do
    summary = build_account_summary(account_id, state)
    {:reply, summary, state}
  end

  @impl true
  def handle_call({:can_place_order, account_id, order_params}, _from, state) do
    result = check_order_allowed(account_id, order_params, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_strategies, account_id}, _from, state) do
    strategies = Map.get(state.accounts, account_id, %{}) |> Map.values()
    {:reply, strategies, state}
  end

  @impl true
  def handle_call({:get_position, account_id, symbol}, _from, state) do
    position = SharedPositionTracker.get_position(account_id, symbol)
    {:reply, position, state}
  end

  @impl true
  def handle_call(:list_accounts, _from, state) do
    {:reply, Map.keys(state.accounts), state}
  end

  @impl true
  def handle_info({:strategy_activated, setting}, state) do
    new_state = add_strategy(setting, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:strategy_deactivated, setting}, state) do
    new_state = remove_strategy(setting, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:strategy_auto_stopped, setting, reason}, state) do
    Logger.info("Strategy #{setting.id} auto-stopped: #{reason}")
    new_state = remove_strategy(setting, state)

    # If max_daily_loss, stop all strategies on account
    if reason == :max_daily_loss do
      stop_all_account_strategies(setting.account_id, state)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:conditions_met, _setting}, state) do
    # Handled by StrategyManager
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp add_strategy(setting, state) do
    account_id = setting.account_id

    strategy_info = %{
      id: setting.id,
      name: setting.strategy_name,
      type: setting.strategy_name,
      symbol: setting.config["symbol"],
      activated_at: DateTime.utc_now(),
      config: setting.config
    }

    account_strategies =
      state.accounts
      |> Map.get(account_id, %{})
      |> Map.put(setting.id, strategy_info)

    Logger.debug("Added strategy #{setting.id} to account #{account_id}")

    %{state | accounts: Map.put(state.accounts, account_id, account_strategies)}
  end

  defp remove_strategy(setting, state) do
    account_id = setting.account_id

    account_strategies =
      state.accounts
      |> Map.get(account_id, %{})
      |> Map.delete(setting.id)

    new_accounts =
      if map_size(account_strategies) == 0 do
        Map.delete(state.accounts, account_id)
      else
        Map.put(state.accounts, account_id, account_strategies)
      end

    Logger.debug("Removed strategy #{setting.id} from account #{account_id}")

    %{state | accounts: new_accounts}
  end

  defp build_account_summary(account_id, state) do
    strategies = Map.get(state.accounts, account_id, %{}) |> Map.values()
    symbols = strategies |> Enum.map(& &1.symbol) |> Enum.uniq()

    positions =
      symbols
      |> Enum.map(fn symbol ->
        {symbol, SharedPositionTracker.get_position(account_id, symbol)}
      end)
      |> Map.new()

    total_pnl =
      positions
      |> Enum.reduce(Decimal.new(0), fn {_symbol, pos}, acc ->
        Decimal.add(acc, pos.unrealized_pnl || Decimal.new(0))
      end)

    %{
      account_id: account_id,
      strategy_count: length(strategies),
      strategies: strategies,
      positions: positions,
      total_unrealized_pnl: total_pnl,
      symbols_traded: symbols
    }
  end

  defp check_order_allowed(account_id, order_params, state) do
    limits = Map.get(state.account_limits, account_id, default_limits())
    symbol = order_params[:symbol] || order_params["symbol"]
    side = order_params[:side] || order_params["side"]
    quantity = parse_quantity(order_params[:quantity] || order_params["quantity"])

    # Get current position
    current_position = SharedPositionTracker.get_position(account_id, symbol)

    # Check max position size
    new_position_size =
      if side == "BUY" do
        Decimal.add(current_position.net_quantity, quantity)
      else
        Decimal.sub(current_position.net_quantity, quantity)
      end

    cond do
      Decimal.compare(Decimal.abs(new_position_size), limits.max_position_size) == :gt ->
        {:error, :max_position_exceeded}

      has_opposing_strategy?(account_id, symbol, side, state) ->
        {:error, :conflicting_strategy}

      true ->
        {:ok, :allowed}
    end
  end

  defp has_opposing_strategy?(account_id, symbol, side, state) do
    strategies = Map.get(state.accounts, account_id, %{}) |> Map.values()

    Enum.any?(strategies, fn strategy ->
      strategy.symbol == symbol and
        get_strategy_direction(strategy) != nil and
        get_strategy_direction(strategy) != side
    end)
  end

  defp get_strategy_direction(strategy) do
    case strategy.type do
      "naive" -> strategy.config["side"]
      "dca" -> strategy.config["side"]
      _ -> nil
    end
  end

  defp default_limits do
    %{
      max_position_size: Decimal.new("1000000"),
      max_daily_loss: Decimal.new("-1000"),
      max_open_orders: 50
    }
  end

  defp parse_quantity(nil), do: Decimal.new(0)
  defp parse_quantity(q) when is_binary(q), do: Decimal.new(q)
  defp parse_quantity(q) when is_number(q), do: Decimal.new("#{q}")
  defp parse_quantity(%Decimal{} = q), do: q

  defp stop_all_account_strategies(account_id, state) do
    strategies = Map.get(state.accounts, account_id, %{}) |> Map.values()

    Enum.each(strategies, fn strategy ->
      Logger.warning("Stopping strategy #{strategy.id} due to account max daily loss")

      Phoenix.PubSub.broadcast(
        BinanceSystem.PubSub,
        @topic,
        {:force_stop_strategy, strategy.id, :account_max_loss}
      )
    end)
  end
end
