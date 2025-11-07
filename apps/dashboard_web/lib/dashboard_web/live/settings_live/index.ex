defmodule DashboardWeb.SettingsLive.Index do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:api_credentials, [])
      |> assign(:trading_settings, %{
        strategy: "naive",
        max_position_size: 2.0,
        stop_loss_percent: 2.0,
        take_profit_percent: 3.0
      })

    {:ok, socket}
  end

  @impl true
  def handle_event("save_settings", params, socket) do
    # TODO: Save settings to database
    {:noreply, put_flash(socket, :info, "Settings saved successfully")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="bg-white shadow rounded-lg p-6">
        <h2 class="text-2xl font-bold mb-6">Settings</h2>

        <div class="space-y-8">
          <div>
            <h3 class="text-lg font-semibold mb-4">API Credentials</h3>
            <%= if Enum.empty?(@api_credentials) do %>
              <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-4">
                <p class="text-sm text-yellow-800">
                  No API credentials configured. Add your Binance API keys to start trading.
                </p>
              </div>
              <.button>Add API Keys</.button>
            <% else %>
              <div class="space-y-3">
                <%= for cred <- @api_credentials do %>
                  <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                    <div>
                      <p class="font-medium"><%= cred.name %></p>
                      <p class="text-sm text-gray-600">
                        <%= if cred.is_testnet, do: "Testnet", else: "Production" %>
                      </p>
                    </div>
                    <div class="flex space-x-2">
                      <.button class="bg-yellow-600 hover:bg-yellow-700">Edit</.button>
                      <.button class="bg-red-600 hover:bg-red-700">Delete</.button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <div>
            <h3 class="text-lg font-semibold mb-4">Trading Settings</h3>
            <form phx-submit="save_settings" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Trading Strategy
                </label>
                <select
                  name="strategy"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                >
                  <option value="naive" selected={@trading_settings.strategy == "naive"}>
                    Naive (Buy Low, Sell High)
                  </option>
                  <option value="grid" selected={@trading_settings.strategy == "grid"}>
                    Grid Trading
                  </option>
                  <option value="dca" selected={@trading_settings.strategy == "dca"}>
                    Dollar Cost Averaging
                  </option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Max Position Size (%)
                </label>
                <input
                  type="number"
                  name="max_position_size"
                  step="0.1"
                  value={@trading_settings.max_position_size}
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                />
                <p class="mt-1 text-sm text-gray-500">
                  Maximum percentage of portfolio to allocate per position
                </p>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Stop Loss (%)
                </label>
                <input
                  type="number"
                  name="stop_loss_percent"
                  step="0.1"
                  value={@trading_settings.stop_loss_percent}
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Take Profit (%)
                </label>
                <input
                  type="number"
                  name="take_profit_percent"
                  step="0.1"
                  value={@trading_settings.take_profit_percent}
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                />
              </div>

              <div class="pt-4">
                <.button type="submit">Save Settings</.button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
