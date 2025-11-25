defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.DecimalHelper
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # Note: User authentication will be added in Phase 8
    # For now, account_id should be passed via session or params

    if connected?(socket) do
      # Subscribe to market and order updates
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
    end

    socket =
      socket
      |> assign(page_title: "Trading")
      |> assign(active_orders: [])
      |> assign(recent_trades: [])
      |> assign(current_price: nil)
      |> assign(account_id: nil)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:execution_report, _data}, socket) do
    # Reload orders when execution report received
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:ticker, %{"c" => price}}, socket) do
    {:noreply, assign(socket, current_price: Decimal.new(price))}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    case cancel_order(order_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Order cancelled successfully")
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel order: #{reason}")}
    end
  end

  defp cancel_order(order_id) do
    with {:ok, order} <- get_order_with_credentials(order_id),
         {:ok, _result} <- execute_cancel(order) do
      # Update order status in database
      order
      |> Order.changeset(%{status: "CANCELED"})
      |> Repo.update()
    end
  end

  defp get_order_with_credentials(order_id) do
    query =
      from o in Order,
        where: o.id == ^order_id,
        preload: [account: :api_credential]

    case Repo.one(query) do
      nil -> {:error, "Order not found"}
      order -> {:ok, order}
    end
  end

  defp execute_cancel(%{account: %{api_credential: nil}}) do
    {:error, "No API credentials configured"}
  end

  defp execute_cancel(%{order_id: nil}) do
    {:error, "Order has no Binance order ID"}
  end

  defp execute_cancel(%{
         order_id: binance_order_id,
         symbol: symbol,
         account: %{api_credential: cred}
       }) do
    DataCollector.BinanceClient.cancel_order(
      cred.api_key,
      cred.secret_key,
      symbol,
      binance_order_id
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-3xl font-bold text-gray-900">Active Trading</h1>
        <%= if @current_price do %>
          <div class="text-right">
            <div class="text-sm text-gray-500">BTC/USDT</div>
            <div class="text-2xl font-bold text-gray-900">
              <%= DecimalHelper.format(@current_price, 2) %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Active Orders -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Active Orders</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@active_orders) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              No active orders
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Symbol</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Side</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Price</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Quantity</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Filled</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for order <- @active_orders do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= order.symbol %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= order.type %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        if(order.side == "BUY", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                      ]}>
                        <%= order.side %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= if order.price, do: DecimalHelper.format(order.price, 2), else: "MARKET" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(order.quantity, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(order.filled_qty, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class="px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                        <%= order.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <button
                        phx-click="cancel_order"
                        phx-value-id={order.id}
                        class="text-red-600 hover:text-red-900"
                      >
                        Cancel
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <!-- Recent Trades -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Recent Trades</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@recent_trades) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              No recent trades
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Symbol</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Side</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Price</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Quantity</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for trade <- @recent_trades do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= Calendar.strftime(trade.timestamp, "%H:%M:%S") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= trade.symbol %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        if(trade.side == "BUY", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                      ]}>
                        <%= trade.side %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.price, 2) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.quantity, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
                      <%= if trade.pnl do %>
                        <span class={[
                          "font-medium",
                          if(DecimalHelper.positive?(trade.pnl), do: "text-green-600", else: "text-red-600")
                        ]}>
                          <%= DecimalHelper.format_currency(trade.pnl, "USDT", 2) %>
                        </span>
                      <% else %>
                        <span class="text-gray-400">-</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_data(socket) do
    # Phase 8: Will load data based on authenticated user's account
    # Currently returns empty data until user authentication is implemented
    socket
    |> assign(active_orders: load_active_orders(socket.assigns.account_id))
    |> assign(recent_trades: load_recent_trades(socket.assigns.account_id))
  end

  defp load_active_orders(nil), do: []

  defp load_active_orders(account_id) do
    query =
      from o in Order,
        where: o.account_id == ^account_id,
        where: o.status in ["NEW", "PARTIALLY_FILLED"],
        order_by: [desc: o.inserted_at],
        limit: 50

    Repo.all(query)
  end

  defp load_recent_trades(nil), do: []

  defp load_recent_trades(account_id) do
    alias SharedData.Schemas.Trade

    query =
      from t in Trade,
        where: t.account_id == ^account_id,
        order_by: [desc: t.timestamp],
        limit: 20

    Repo.all(query)
  end
end
