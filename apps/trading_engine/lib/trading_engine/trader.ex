defmodule TradingEngine.Trader do
  @moduledoc """
  GenServer that manages trading for a single account.

  Each trader process is responsible for:
  - Executing a trading strategy
  - Managing positions
  - Placing and tracking orders
  - Risk management
  """

  use GenServer
  require Logger

  defstruct [
    :user_id,
    :api_key,
    :secret_key,
    :strategy,
    :status,
    :positions,
    :orders,
    :balance
  ]

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(user_id))
  end

  def init(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    api_key = Keyword.fetch!(opts, :api_key)
    secret_key = Keyword.fetch!(opts, :secret_key)
    strategy = Keyword.get(opts, :strategy, :naive)

    state = %__MODULE__{
      user_id: user_id,
      api_key: api_key,
      secret_key: secret_key,
      strategy: strategy,
      status: :initializing,
      positions: %{},
      orders: %{},
      balance: %{}
    }

    # Subscribe to market data
    DataCollector.subscribe()

    # Initialize account data
    send(self(), :initialize)

    {:ok, state}
  end

  @doc """
  Start trading for a user account.
  """
  def start_trading(user_id, api_key, secret_key, strategy \\ :naive) do
    DynamicSupervisor.start_child(
      TradingEngine.AccountSupervisor,
      {__MODULE__, [user_id: user_id, api_key: api_key, secret_key: secret_key, strategy: strategy]}
    )
  end

  @doc """
  Stop trading for a user account.
  """
  def stop_trading(user_id) do
    case GenServer.whereis(via_tuple(user_id)) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(TradingEngine.AccountSupervisor, pid)
    end
  end

  @doc """
  Get current trader state.
  """
  def get_state(user_id) do
    GenServer.call(via_tuple(user_id), :get_state)
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_info(:initialize, state) do
    Logger.info("Initializing trader for user #{state.user_id}")

    # Fetch initial balance
    case DataCollector.get_balances(state.api_key, state.secret_key) do
      {:ok, balances} ->
        Logger.info("Loaded balances for user #{state.user_id}")
        new_state = %{state | balance: balances, status: :active}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to load balances: #{inspect(reason)}")
        new_state = %{state | status: :error}
        {:noreply, new_state}
    end
  end

  def handle_info({:price_update, prices}, state) do
    # Handle price updates from market data
    # Execute trading strategy based on new prices
    case state.strategy do
      :naive ->
        handle_naive_strategy(prices, state)

      :grid ->
        handle_grid_strategy(prices, state)

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_naive_strategy(_prices, state) do
    # TODO: Implement naive strategy logic
    {:noreply, state}
  end

  defp handle_grid_strategy(_prices, state) do
    # TODO: Implement grid strategy logic
    {:noreply, state}
  end

  defp via_tuple(user_id) do
    {:via, Registry, {TradingEngine.Registry, user_id}}
  end
end
