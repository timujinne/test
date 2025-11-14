defmodule DashboardWeb.HistoryLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.DecimalHelper

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "History")
      |> assign(trades: [])
      |> assign(page: 1)
      |> assign(per_page: 20)
      |> assign(total_pages: 1)
      |> assign(filter_symbol: nil)
      |> assign(account_id: nil)
      |> load_trades()

    {:ok, socket}
  end

  @impl true
  def handle_event("prev_page", _, socket) do
    if socket.assigns.page > 1 do
      {:noreply, socket |> assign(page: socket.assigns.page - 1) |> load_trades()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_page", _, socket) do
    if socket.assigns.page < socket.assigns.total_pages do
      {:noreply, socket |> assign(page: socket.assigns.page + 1) |> load_trades()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_symbol", %{"symbol" => symbol}, socket) do
    filter = if symbol == "", do: nil, else: symbol
    {:noreply, socket |> assign(filter_symbol: filter, page: 1) |> load_trades()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Trade History</h1>
          <p class="mt-2 text-sm text-gray-600">
            View your past trades and performance
          </p>
        </div>
      </div>

      <!-- Filters -->
      <div class="bg-white shadow rounded-lg p-4">
        <div class="flex items-center space-x-4">
          <div class="flex-1">
            <label for="symbol-filter" class="block text-sm font-medium text-gray-700">
              Filter by Symbol
            </label>
            <input
              type="text"
              id="symbol-filter"
              phx-change="filter_symbol"
              name="symbol"
              value={@filter_symbol || ""}
              placeholder="e.g. BTCUSDT"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            />
          </div>
        </div>
      </div>

      <!-- Trades Table -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">All Trades</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@trades) do %>
            <div class="px-6 py-12 text-center">
              <svg
                class="mx-auto h-12 w-12 text-gray-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                />
              </svg>
              <h3 class="mt-2 text-sm font-medium text-gray-900">No trades</h3>
              <p class="mt-1 text-sm text-gray-500">
                <%= if @filter_symbol do %>
                  No trades found for <%= @filter_symbol %>
                <% else %>
                  No trades have been executed yet.
                <% end %>
              </p>
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Date/Time
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Symbol
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Side
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Price
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Total
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Commission
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    P&L
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for trade <- @trades do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= Calendar.strftime(trade.timestamp, "%Y-%m-%d %H:%M:%S") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="text-sm font-medium text-gray-900">
                        <%= trade.symbol %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        if(trade.side == "BUY",
                          do: "bg-green-100 text-green-800",
                          else: "bg-red-100 text-red-800"
                        )
                      ]}>
                        <%= trade.side %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.price, 2) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.quantity, 8) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(Decimal.mult(trade.price, trade.quantity), 2) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 text-right">
                      <%= if trade.commission do %>
                        <%= DecimalHelper.format(trade.commission, 8) %>
                        <%= if trade.commission_asset, do: trade.commission_asset, else: "" %>
                      <% else %>
                        -
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
                      <%= if trade.pnl do %>
                        <span class={[
                          "font-medium",
                          if(DecimalHelper.positive?(trade.pnl),
                            do: "text-green-600",
                            else: "text-red-600"
                          )
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

            <!-- Pagination -->
            <div class="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6">
              <div class="flex-1 flex justify-between sm:hidden">
                <button
                  phx-click="prev_page"
                  disabled={@page == 1}
                  class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
                >
                  Previous
                </button>
                <button
                  phx-click="next_page"
                  disabled={@page >= @total_pages}
                  class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
                >
                  Next
                </button>
              </div>
              <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
                <div>
                  <p class="text-sm text-gray-700">
                    Page <span class="font-medium"><%= @page %></span>
                    of
                    <span class="font-medium"><%= @total_pages %></span>
                  </p>
                </div>
                <div>
                  <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px">
                    <button
                      phx-click="prev_page"
                      disabled={@page == 1}
                      class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50"
                    >
                      <span class="sr-only">Previous</span>
                      ←
                    </button>
                    <button
                      phx-click="next_page"
                      disabled={@page >= @total_pages}
                      class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50"
                    >
                      <span class="sr-only">Next</span>
                      →
                    </button>
                  </nav>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_trades(socket) do
    # TODO: Load real data based on current user account and filters
    socket
    |> assign(trades: [])
    |> assign(total_pages: 1)
  end
end
