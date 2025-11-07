defmodule DashboardWeb.PortfolioLive.Index do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Portfolio")
      |> assign(:balances, [])
      |> assign(:total_value_usd, Decimal.new(0))
      |> assign(:pnl_24h, Decimal.new(0))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-2xl font-bold mb-6">Portfolio Overview</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
          <div class="bg-blue-50 p-4 rounded-lg">
            <p class="text-sm text-gray-600 mb-1">Total Value</p>
            <p class="text-2xl font-bold text-blue-600">
              $<%= Decimal.to_string(@total_value_usd, :normal) %>
            </p>
          </div>

          <div class="bg-green-50 p-4 rounded-lg">
            <p class="text-sm text-gray-600 mb-1">24h PnL</p>
            <p class={[
              "text-2xl font-bold",
              Decimal.compare(@pnl_24h, 0) == :gt && "text-green-600",
              Decimal.compare(@pnl_24h, 0) == :lt && "text-red-600",
              Decimal.compare(@pnl_24h, 0) == :eq && "text-gray-600"
            ]}>
              <%= if Decimal.compare(@pnl_24h, 0) == :gt, do: "+", else: "" %><%= Decimal.to_string(
                @pnl_24h,
                :normal
              ) %>%
            </p>
          </div>

          <div class="bg-purple-50 p-4 rounded-lg">
            <p class="text-sm text-gray-600 mb-1">Assets</p>
            <p class="text-2xl font-bold text-purple-600"><%= length(@balances) %></p>
          </div>
        </div>

        <h3 class="text-lg font-semibold mb-3">Balances</h3>
        <%= if Enum.empty?(@balances) do %>
          <div class="text-center py-8">
            <p class="text-gray-500 mb-4">No balances available</p>
            <.button>Connect API Keys</.button>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Asset
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Free
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Locked
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Total
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for balance <- @balances do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap font-medium"><%= balance.asset %></td>
                    <td class="px-6 py-4 whitespace-nowrap"><%= balance.free %></td>
                    <td class="px-6 py-4 whitespace-nowrap"><%= balance.locked %></td>
                    <td class="px-6 py-4 whitespace-nowrap font-semibold"><%= balance.total %></td>
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
