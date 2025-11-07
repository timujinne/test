defmodule DashboardWeb.TradingLive.Index do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      DataCollector.subscribe()
    end

    socket =
      socket
      |> assign(:page_title, "Trading")
      |> assign(:prices, %{})
      |> assign(:active_traders, [])
      |> assign(:recent_orders, [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:price_update, prices}, socket) do
    {:noreply, assign(socket, :prices, prices)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-2xl font-bold mb-4">Active Trading</h2>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h3 class="text-lg font-semibold mb-3">Market Prices</h3>
            <div class="space-y-2">
              <%= for {symbol, price} <- @prices do %>
                <div class="flex justify-between items-center p-3 bg-gray-50 rounded">
                  <span class="font-medium"><%= symbol %></span>
                  <span class="font-mono text-lg"><%= price %></span>
                </div>
              <% end %>
              <%= if Enum.empty?(@prices) do %>
                <p class="text-gray-500">No market data available</p>
              <% end %>
            </div>
          </div>

          <div>
            <h3 class="text-lg font-semibold mb-3">Active Traders</h3>
            <div class="space-y-2">
              <%= if Enum.empty?(@active_traders) do %>
                <p class="text-gray-500">No active traders</p>
                <.button phx-click="start_trader" class="mt-4">
                  Start Trading
                </.button>
              <% else %>
                <%= for trader <- @active_traders do %>
                  <div class="p-3 bg-gray-50 rounded">
                    <p class="font-medium">Trader <%= trader.id %></p>
                    <p class="text-sm text-gray-600">Strategy: <%= trader.strategy %></p>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg p-6">
        <h3 class="text-lg font-semibold mb-3">Recent Orders</h3>
        <%= if Enum.empty?(@recent_orders) do %>
          <p class="text-gray-500">No recent orders</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Symbol
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Side
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Price
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Status
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for order <- @recent_orders do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap"><%= order.symbol %></td>
                    <td class="px-6 py-4 whitespace-nowrap"><%= order.side %></td>
                    <td class="px-6 py-4 whitespace-nowrap"><%= order.price %></td>
                    <td class="px-6 py-4 whitespace-nowrap"><%= order.status %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
