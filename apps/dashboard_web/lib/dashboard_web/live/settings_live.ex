defmodule DashboardWeb.SettingsLive do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Settings")
      |> assign(accounts: [])
      |> assign(strategies: [])
      |> assign(selected_tab: "accounts")
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: tab)}
  end

  @impl true
  def handle_event("activate_strategy", %{"id" => _strategy_id}, socket) do
    # TODO: Implement strategy activation
    {:noreply, put_flash(socket, :info, "Strategy activation requested")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-gray-900">Settings</h1>
        <p class="mt-2 text-sm text-gray-600">
          Manage your accounts, API credentials, and trading strategies
        </p>
      </div>

      <!-- Tabs -->
      <div class="border-b border-gray-200">
        <nav class="-mb-px flex space-x-8">
          <button
            phx-click="select_tab"
            phx-value-tab="accounts"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
              if(@selected_tab == "accounts",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Accounts
          </button>
          <button
            phx-click="select_tab"
            phx-value-tab="strategies"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
              if(@selected_tab == "strategies",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Strategies
          </button>
          <button
            phx-click="select_tab"
            phx-value-tab="api"
            class={[
              "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
              if(@selected_tab == "api",
                do: "border-indigo-500 text-indigo-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            API Credentials
          </button>
        </nav>
      </div>

      <!-- Accounts Tab -->
      <%= if @selected_tab == "accounts" do %>
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <h2 class="text-xl font-semibold text-gray-900">Trading Accounts</h2>
            <button class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
              Add Account
            </button>
          </div>
          <div class="p-6">
            <%= if Enum.empty?(@accounts) do %>
              <div class="text-center text-gray-500 py-8">
                No accounts configured. Add your first Binance account to start trading.
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for account <- @accounts do %>
                  <div class="border border-gray-200 rounded-lg p-4">
                    <div class="flex justify-between items-start">
                      <div>
                        <h3 class="text-lg font-medium text-gray-900"><%= account.label %></h3>
                        <%= if account.binance_account_id do %>
                          <p class="text-sm text-gray-500">ID: <%= account.binance_account_id %></p>
                        <% end %>
                        <div class="mt-2">
                          <span class={[
                            "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                            if(account.is_active,
                              do: "bg-green-100 text-green-800",
                              else: "bg-gray-100 text-gray-800"
                            )
                          ]}>
                            <%= if account.is_active, do: "Active", else: "Inactive" %>
                          </span>
                        </div>
                      </div>
                      <div class="flex space-x-2">
                        <button class="text-indigo-600 hover:text-indigo-900">Edit</button>
                        <button class="text-red-600 hover:text-red-900">Delete</button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Strategies Tab -->
      <%= if @selected_tab == "strategies" do %>
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <h2 class="text-xl font-semibold text-gray-900">Trading Strategies</h2>
            <button class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
              Create Strategy
            </button>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <!-- Naive Strategy -->
              <div class="border border-gray-200 rounded-lg p-6">
                <h3 class="text-lg font-medium text-gray-900">Naive</h3>
                <p class="mt-2 text-sm text-gray-600">
                  Simple buy-low, sell-high strategy. Good for beginners.
                </p>
                <div class="mt-4">
                  <button class="w-full px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
                    Configure
                  </button>
                </div>
              </div>

              <!-- Grid Strategy -->
              <div class="border border-gray-200 rounded-lg p-6">
                <h3 class="text-lg font-medium text-gray-900">Grid Trading</h3>
                <p class="mt-2 text-sm text-gray-600">
                  Place buy and sell orders at different price levels.
                </p>
                <div class="mt-4">
                  <button class="w-full px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
                    Configure
                  </button>
                </div>
              </div>

              <!-- DCA Strategy -->
              <div class="border border-gray-200 rounded-lg p-6">
                <h3 class="text-lg font-medium text-gray-900">DCA</h3>
                <p class="mt-2 text-sm text-gray-600">
                  Dollar Cost Averaging - buy at regular intervals.
                </p>
                <div class="mt-4">
                  <button class="w-full px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
                    Configure
                  </button>
                </div>
              </div>
            </div>

            <%= if !Enum.empty?(@strategies) do %>
              <div class="mt-8">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Active Strategies</h3>
                <div class="space-y-4">
                  <%= for strategy <- @strategies do %>
                    <div class="border border-gray-200 rounded-lg p-4 flex justify-between items-center">
                      <div>
                        <h4 class="font-medium text-gray-900"><%= strategy.strategy_name %></h4>
                        <p class="text-sm text-gray-500">
                          <%= if strategy.is_active, do: "Running", else: "Stopped" %>
                        </p>
                      </div>
                      <div class="flex space-x-2">
                        <%= if strategy.is_active do %>
                          <button class="px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700 text-sm">
                            Stop
                          </button>
                        <% else %>
                          <button
                            phx-click="activate_strategy"
                            phx-value-id={strategy.id}
                            class="px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700 text-sm"
                          >
                            Start
                          </button>
                        <% end %>
                        <button class="px-3 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 text-sm">
                          Edit
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- API Credentials Tab -->
      <%= if @selected_tab == "api" do %>
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <h2 class="text-xl font-semibold text-gray-900">API Credentials</h2>
            <button class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
              Add Credentials
            </button>
          </div>
          <div class="p-6">
            <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-6">
              <div class="flex">
                <div class="flex-shrink-0">
                  <svg
                    class="h-5 w-5 text-yellow-400"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </div>
                <div class="ml-3">
                  <p class="text-sm text-yellow-700">
                    <strong>Security Notice:</strong>
                    Your API keys are encrypted in the database. Never share your API keys with anyone.
                  </p>
                </div>
              </div>
            </div>

            <div class="text-center text-gray-500 py-8">
              API credentials management will be displayed here
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_data(socket) do
    # TODO: Load real data based on current user
    socket
    |> assign(accounts: [])
    |> assign(strategies: [])
  end
end
