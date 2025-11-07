defmodule TradingEngine.OrderManager do
  @moduledoc """
  Manages orders across all trading accounts.

  Tracks order status, handles order updates, and maintains order history.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    state = %{
      orders: %{},
      pending_orders: MapSet.new()
    }

    {:ok, state}
  end

  @doc """
  Place a new order.
  """
  def place_order(user_id, api_key, secret_key, order_params) do
    GenServer.call(__MODULE__, {:place_order, user_id, api_key, secret_key, order_params})
  end

  @doc """
  Cancel an order.
  """
  def cancel_order(user_id, api_key, secret_key, symbol, order_id) do
    GenServer.call(__MODULE__, {:cancel_order, user_id, api_key, secret_key, symbol, order_id})
  end

  @doc """
  Get order status.
  """
  def get_order(order_id) do
    GenServer.call(__MODULE__, {:get_order, order_id})
  end

  def handle_call({:place_order, user_id, api_key, secret_key, order_params}, _from, state) do
    Logger.info("Placing order for user #{user_id}: #{inspect(order_params)}")

    case DataCollector.place_order(api_key, secret_key, order_params) do
      {:ok, order} ->
        # Store order in state
        order_id = Map.get(order, :order_id, System.unique_integer([:positive]))
        new_orders = Map.put(state.orders, order_id, order)
        new_pending = MapSet.put(state.pending_orders, order_id)

        new_state = %{state | orders: new_orders, pending_orders: new_pending}
        {:reply, {:ok, order}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to place order: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:cancel_order, user_id, api_key, secret_key, symbol, order_id}, _from, state) do
    Logger.info("Canceling order #{order_id} for user #{user_id}")

    case DataCollector.cancel_order(api_key, secret_key, symbol, order_id) do
      {:ok, result} ->
        # Remove from pending orders
        new_pending = MapSet.delete(state.pending_orders, order_id)
        new_state = %{state | pending_orders: new_pending}
        {:reply, {:ok, result}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to cancel order: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:get_order, order_id}, _from, state) do
    order = Map.get(state.orders, order_id)
    {:reply, order, state}
  end
end
