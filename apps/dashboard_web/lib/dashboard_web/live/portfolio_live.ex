defmodule DashboardWeb.PortfolioLive do
  use DashboardWeb, :live_view
  
  alias SharedData.{Accounts, Trading}
  alias SharedData.Helpers.DecimalHelper

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "balance_updates")
    end

    socket =
      socket
      |> assign(page_title: "Portfolio")
      |> assign(balances: [])
      |> assign(total_value: Decimal.new(0))
      |> assign(total_pnl: Decimal.new(0))
      |> assign(account_id: nil)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:balance_update, _data}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-gray-900">Portfolio Overview</h1>
        <p class="mt-2 text-sm text-gray-600">
          View your account balances and P&L summary
        </p>
      </div>

      <!-- Summary Cards -->
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-3">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <dt class="text-sm font-medium text-gray-500 truncate">
              Total Value
            </dt>
            <dd class="mt-1 text-3xl font-semibold text-gray-900">
              <%= DecimalHelper.format_currency(@total_value, "USDT", 2) %>
            </dd>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <dt class="text-sm font-medium text-gray-500 truncate">
              Total P&L
            </dt>
            <dd class={[
              "mt-1 text-3xl font-semibold",
              if(DecimalHelper.positive?(@total_pnl), do: "text-green-600", else: "text-red-600")
            ]}>
              <%= DecimalHelper.format_currency(@total_pnl, "USDT", 2) %>
            </dd>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="px-4 py-5 sm:p-6">
            <dt class="text-sm font-medium text-gray-500 truncate">
              Assets
            </dt>
            <dd class="mt-1 text-3xl font-semibold text-gray-900">
              <%= length(@balances) %>
            </dd>
          </div>
        </div>
      </div>

      <!-- Balances Table -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Asset Balances</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@balances) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              No assets found. Connect your Binance account to see balances.
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Asset</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Free</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Locked</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Total</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Value (USDT)</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for balance <- @balances do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <div class="text-sm font-medium text-gray-900">
                          <%= balance.asset %>
                        </div>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(balance.free, 8) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(balance.locked, 8) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 text-right">
                      <%= DecimalHelper.format(balance.total, 8) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= calculate_value(balance) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <!-- Performance Chart Placeholder -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Performance</h2>
        </div>
        <div class="px-6 py-8">
          <div class="text-center text-gray-500">
            Performance chart will be displayed here
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_data(socket) do
    # TODO: Load real data based on current user account
    socket
    |> assign(balances: [])
    |> assign(total_value: Decimal.new(0))
    |> assign(total_pnl: Decimal.new(0))
  end

  defp calculate_value(balance) do
    # TODO: Calculate USDT value based on current prices
    # For now, return dash
    "-"
  end
end
