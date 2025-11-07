defmodule DashboardWeb.DashboardLive.Index do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to market data updates
      DataCollector.subscribe()
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:prices, %{})
      |> assign(:active_traders, 0)

    {:ok, socket}
  end

  @impl true
  def handle_info({:price_update, prices}, socket) do
    {:noreply, assign(socket, :prices, prices)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6">Binance Trading Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
        <div class="bg-white p-6 rounded-lg shadow">
          <h3 class="text-lg font-semibold mb-2">Market Prices</h3>
          <div class="space-y-2">
            <%= for {symbol, price} <- @prices do %>
              <div class="flex justify-between">
                <span><%= symbol %></span>
                <span class="font-mono"><%= price %></span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-white p-6 rounded-lg shadow">
          <h3 class="text-lg font-semibold mb-2">Active Traders</h3>
          <p class="text-4xl font-bold"><%= @active_traders %></p>
        </div>

        <div class="bg-white p-6 rounded-lg shadow">
          <h3 class="text-lg font-semibold mb-2">Quick Actions</h3>
          <div class="space-y-2">
            <.link navigate={~p"/trading"} class="block px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
              View Trading
            </.link>
            <.link navigate={~p"/portfolio"} class="block px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">
              View Portfolio
            </.link>
          </div>
        </div>
      </div>

      <div class="bg-white p-6 rounded-lg shadow">
        <h3 class="text-lg font-semibold mb-4">Getting Started</h3>
        <ol class="list-decimal list-inside space-y-2">
          <li>Configure your Binance API keys in Settings</li>
          <li>Choose a trading strategy</li>
          <li>Start your trader</li>
          <li>Monitor performance in real-time</li>
        </ol>
      </div>
    </div>
    """
  end
end
