defmodule DashboardWeb.OrdersLive do
  @moduledoc """
  LiveView for managing open orders across all symbols.
  Allows viewing, filtering, and cancelling orders.
  """
  use DashboardWeb, :live_view

  alias SharedData.Helpers.CredentialHelper
  alias DataCollector.BinanceClient

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to order updates for real-time changes
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "orders:all")
      # Refresh orders every 30 seconds
      :timer.send_interval(30_000, self(), :refresh_orders)
    end

    socket =
      socket
      |> assign(page_title: "Orders")
      |> assign(current_path: "/app/orders")
      |> assign(orders: [])
      |> assign(grouped_orders: %{})
      |> assign(available_symbols: [])
      |> assign(selected_symbol: "all")
      |> assign(loading: true)
      |> assign(error: nil)
      |> assign(cancelling: MapSet.new())
      # New order form state
      |> assign(show_new_order_modal: false)
      |> assign(new_order_form: default_order_form())
      |> assign(creating_order: false)
      |> assign(all_symbols: [])
      |> assign(filtered_symbols: [])
      |> assign(symbol_search: "")

    # Load orders and symbols after mount
    send(self(), :load_orders)
    send(self(), :load_symbols)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_orders, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_info(:load_symbols, socket) do
    {:noreply, load_symbols(socket)}
  end

  @impl true
  def handle_info(:refresh_orders, socket) do
    {:noreply, load_orders(socket)}
  end

  # Handle real-time order updates
  @impl true
  def handle_info({:order_created, _order}, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_info({:order_filled, _execution}, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_info({:order_cancelled, _execution}, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_info({:order_partially_filled, _execution}, socket) do
    {:noreply, load_orders(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_symbol", params, socket) do
    symbol = params["symbol"] || "all"
    {:noreply, assign(socket, selected_symbol: symbol)}
  end

  @impl true
  def handle_event("cancel_order", %{"symbol" => symbol, "order-id" => order_id}, socket) do
    order_id_int = String.to_integer(order_id)

    # Mark order as cancelling
    socket = update(socket, :cancelling, &MapSet.put(&1, order_id_int))

    case get_credentials() do
      {api_key, secret_key} ->
        case BinanceClient.cancel_order(api_key, secret_key, symbol, order_id_int) do
          {:ok, _result} ->
            socket =
              socket
              |> put_flash(:info, "Order #{order_id} cancelled successfully")
              |> update(:cancelling, &MapSet.delete(&1, order_id_int))
              |> load_orders()

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> put_flash(:error, "Failed to cancel order: #{inspect(reason)}")
              |> update(:cancelling, &MapSet.delete(&1, order_id_int))

            {:noreply, socket}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "No API credentials configured")}
    end
  end

  @impl true
  def handle_event("cancel_all_for_symbol", %{"symbol" => symbol}, socket) do
    case get_credentials() do
      {api_key, secret_key} ->
        case BinanceClient.cancel_all_orders(api_key, secret_key, symbol) do
          {:ok, cancelled} ->
            count = length(cancelled)

            socket =
              socket
              |> put_flash(:info, "Cancelled #{count} orders for #{symbol}")
              |> load_orders()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel orders: #{inspect(reason)}")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "No API credentials configured")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(loading: true) |> load_orders()}
  end

  # New order modal events
  @impl true
  def handle_event("open_new_order_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(show_new_order_modal: true)
     |> assign(new_order_form: default_order_form())
     |> assign(symbol_search: "")
     |> assign(filtered_symbols: [])}
  end

  @impl true
  def handle_event("close_new_order_modal", _params, socket) do
    {:noreply, assign(socket, show_new_order_modal: false)}
  end

  @impl true
  def handle_event("search_symbol", %{"value" => query}, socket) do
    filtered =
      if String.length(query) >= 1 do
        query_upper = String.upcase(query)

        socket.assigns.all_symbols
        |> Enum.filter(&String.contains?(&1, query_upper))
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(symbol_search: query)
     |> assign(filtered_symbols: filtered)}
  end

  @impl true
  def handle_event("select_symbol", %{"symbol" => symbol}, socket) do
    form = Map.put(socket.assigns.new_order_form, "symbol", symbol)

    {:noreply,
     socket
     |> assign(new_order_form: form)
     |> assign(symbol_search: symbol)
     |> assign(filtered_symbols: [])}
  end

  @impl true
  def handle_event("update_order_form", %{"order" => params}, socket) do
    form = Map.merge(socket.assigns.new_order_form, params)
    {:noreply, assign(socket, new_order_form: form)}
  end

  @impl true
  def handle_event("create_order", _params, socket) do
    form = socket.assigns.new_order_form

    with :ok <- validate_order_form(form),
         {api_key, secret_key} <- get_credentials() do
      socket = assign(socket, creating_order: true)

      order_params = build_order_params(form)

      case BinanceClient.create_order(api_key, secret_key, order_params) do
        {:ok, order} ->
          {:noreply,
           socket
           |> assign(creating_order: false)
           |> assign(show_new_order_modal: false)
           |> assign(new_order_form: default_order_form())
           |> put_flash(:info, "Order created: #{order["orderId"]}")
           |> load_orders()}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(creating_order: false)
           |> put_flash(:error, "Failed to create order: #{format_error(reason)}")}
      end
    else
      {:error, msg} ->
        {:noreply, put_flash(socket, :error, msg)}

      nil ->
        {:noreply, put_flash(socket, :error, "No API credentials configured")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-base-content">Open Orders</h1>
          <p class="mt-2 text-sm text-base-content/70">
            Manage your open orders across all trading pairs
          </p>
        </div>
        <div class="flex gap-2">
          <button
            class="btn btn-success"
            phx-click="open_new_order_modal"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New Order
          </button>
          <button
            class="btn btn-primary"
            phx-click="refresh"
            disabled={@loading}
          >
            <%= if @loading do %>
              <span class="loading loading-spinner loading-sm"></span>
            <% else %>
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
            <% end %>
            Refresh
          </button>
        </div>
      </div>

      <!-- Stats Cards -->
      <div class="stats shadow w-full">
        <div class="stat">
          <div class="stat-title">Total Orders</div>
          <div class="stat-value text-primary"><%= length(@orders) %></div>
        </div>
        <div class="stat">
          <div class="stat-title">Symbols</div>
          <div class="stat-value text-secondary"><%= length(@available_symbols) %></div>
        </div>
        <div class="stat">
          <div class="stat-title">Buy Orders</div>
          <div class="stat-value text-success"><%= count_by_side(@orders, "BUY") %></div>
        </div>
        <div class="stat">
          <div class="stat-title">Sell Orders</div>
          <div class="stat-value text-error"><%= count_by_side(@orders, "SELL") %></div>
        </div>
      </div>

      <!-- Error Alert -->
      <%= if @error do %>
        <div class="alert alert-error">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span><%= @error %></span>
        </div>
      <% end %>

      <!-- Filter -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body py-4">
          <div class="flex items-center gap-4">
            <form phx-change="filter_symbol" class="form-control w-full max-w-xs">
              <div class="label">
                <span class="label-text font-medium">Filter by Symbol</span>
              </div>
              <select
                id="symbol-filter"
                class="select select-bordered"
                name="symbol"
              >
                <option value="all" selected={@selected_symbol == "all"}>
                  All Symbols (<%= length(@orders) %>)
                </option>
                <%= for symbol <- @available_symbols do %>
                  <option value={symbol} selected={@selected_symbol == symbol}>
                    <%= symbol %> (<%= Map.get(@grouped_orders, symbol, []) |> length() %>)
                  </option>
                <% end %>
              </select>
            </form>

            <!-- Quick filter buttons -->
            <div class="flex gap-1 items-center">
              <button
                class={["btn btn-sm", if(@selected_symbol == "all", do: "btn-primary", else: "btn-ghost")]}
                phx-click="filter_symbol"
                phx-value-symbol="all"
              >
                All
              </button>
              <%= for symbol <- @available_symbols do %>
                <button
                  class={["btn btn-sm", if(@selected_symbol == symbol, do: "btn-primary", else: "btn-ghost")]}
                  phx-click="filter_symbol"
                  phx-value-symbol={symbol}
                >
                  <%= symbol %>
                </button>
              <% end %>
            </div>

            <%= if @selected_symbol != "all" do %>
              <div class="flex-1"></div>
              <button
                class="btn btn-error btn-outline"
                phx-click="cancel_all_for_symbol"
                phx-value-symbol={@selected_symbol}
                data-confirm={"Are you sure you want to cancel all #{Map.get(@grouped_orders, @selected_symbol, []) |> length()} orders for #{@selected_symbol}?"}
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
                Cancel All <%= @selected_symbol %>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Current filter indicator -->
      <%= if @selected_symbol != "all" do %>
        <div class="alert alert-info mb-4">
          <span>Showing orders for: <strong><%= @selected_symbol %></strong> (<%= length(filtered_orders(@orders, @grouped_orders, @selected_symbol)) %> of <%= length(@orders) %> orders)</span>
          <button class="btn btn-sm btn-ghost" phx-click="filter_symbol" phx-value-symbol="all">Clear filter</button>
        </div>
      <% end %>

      <!-- Orders Table -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body p-0">
          <%= if @loading and Enum.empty?(@orders) do %>
            <div class="flex justify-center items-center py-12">
              <span class="loading loading-spinner loading-lg text-primary"></span>
            </div>
          <% else %>
            <%= if Enum.empty?(filtered_orders(@orders, @grouped_orders, @selected_symbol)) do %>
              <div class="text-center py-12">
                <svg class="mx-auto h-12 w-12 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                <h3 class="mt-2 text-sm font-medium text-base-content">No open orders</h3>
                <p class="mt-1 text-sm text-base-content/70">
                  You don't have any open orders at the moment.
                </p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-zebra">
                  <thead>
                    <tr>
                      <th>Time</th>
                      <th>Symbol</th>
                      <th>Side</th>
                      <th>Type</th>
                      <th class="text-right">Price</th>
                      <th class="text-right">Quantity</th>
                      <th class="text-right">Filled</th>
                      <th class="text-right">Total</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for order <- filtered_orders(@orders, @grouped_orders, @selected_symbol) do %>
                      <tr class={if MapSet.member?(@cancelling, order["orderId"]), do: "opacity-50"}>
                        <td class="text-xs text-base-content/70">
                          <%= format_timestamp(order["time"]) %>
                        </td>
                        <td>
                          <span class="font-medium"><%= order["symbol"] %></span>
                        </td>
                        <td>
                          <span class={[
                            "badge badge-sm",
                            if(order["side"] == "BUY", do: "badge-success", else: "badge-error")
                          ]}>
                            <%= order["side"] %>
                          </span>
                        </td>
                        <td class="text-base-content/70 text-sm">
                          <%= order["type"] %>
                        </td>
                        <td class="text-right font-mono">
                          <%= format_number_trim(order["price"]) %>
                        </td>
                        <td class="text-right font-mono">
                          <%= format_number_trim(order["origQty"]) %>
                        </td>
                        <td class="text-right font-mono">
                          <span class={if Decimal.compare(Decimal.new(order["executedQty"]), 0) == :gt, do: "text-warning"}>
                            <%= format_number_trim(order["executedQty"]) %>
                          </span>
                        </td>
                        <td class="text-right font-mono text-sm">
                          <%= calculate_total_trim(order["price"], order["origQty"]) %>
                        </td>
                        <td>
                          <button
                            class="btn btn-sm btn-outline btn-error"
                            phx-click="cancel_order"
                            phx-value-symbol={order["symbol"]}
                            phx-value-order-id={order["orderId"]}
                            disabled={MapSet.member?(@cancelling, order["orderId"])}
                            data-confirm="Cancel this order?"
                          >
                            <%= if MapSet.member?(@cancelling, order["orderId"]) do %>
                              <span class="loading loading-spinner loading-sm"></span>
                            <% else %>
                              Cancel
                            <% end %>
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>

      <!-- Per-Symbol Summary -->
      <%= if length(@available_symbols) > 1 do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Orders by Symbol</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
              <%= for symbol <- @available_symbols do %>
                <% symbol_orders = Map.get(@grouped_orders, symbol, []) %>
                <div class="bg-base-200 rounded-lg p-4">
                  <div class="flex justify-between items-center">
                    <span class="font-bold"><%= symbol %></span>
                    <span class="badge"><%= length(symbol_orders) %></span>
                  </div>
                  <div class="mt-2 text-sm text-base-content/70">
                    <div class="flex justify-between">
                      <span>Buy:</span>
                      <span class="text-success"><%= count_by_side(symbol_orders, "BUY") %></span>
                    </div>
                    <div class="flex justify-between">
                      <span>Sell:</span>
                      <span class="text-error"><%= count_by_side(symbol_orders, "SELL") %></span>
                    </div>
                  </div>
                  <button
                    class="btn btn-sm btn-outline btn-error w-full mt-3"
                    phx-click="cancel_all_for_symbol"
                    phx-value-symbol={symbol}
                    data-confirm={"Cancel all #{length(symbol_orders)} orders for #{symbol}?"}
                  >
                    Cancel All
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <!-- New Order Modal -->
      <%= if @show_new_order_modal do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-lg">
            <button
              class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
              phx-click="close_new_order_modal"
            >
              ✕
            </button>
            <h3 class="font-bold text-lg mb-4">Create New Order</h3>

            <form phx-change="update_order_form" phx-submit="create_order" class="space-y-4">
              <!-- Symbol Search -->
              <div class="form-control relative">
                <label class="label">
                  <span class="label-text font-medium">Symbol *</span>
                </label>
                <input
                  type="text"
                  name="order[symbol]"
                  value={@symbol_search}
                  placeholder="Search symbol (e.g., BTCUSDT)"
                  class="input input-bordered w-full"
                  phx-keyup="search_symbol"
                  phx-debounce="200"
                  autocomplete="off"
                />
                <%= if length(@filtered_symbols) > 0 do %>
                  <ul class="menu bg-base-200 rounded-box absolute top-full left-0 right-0 z-50 max-h-48 overflow-y-auto shadow-lg mt-1">
                    <%= for symbol <- @filtered_symbols do %>
                      <li>
                        <button
                          type="button"
                          class="text-left"
                          phx-click="select_symbol"
                          phx-value-symbol={symbol}
                        >
                          <%= symbol %>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>

              <!-- Side Selection -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Side *</span>
                </label>
                <div class="join w-full">
                  <input
                    type="radio"
                    name="order[side]"
                    value="BUY"
                    class="join-item btn flex-1"
                    aria-label="BUY"
                    checked={@new_order_form["side"] == "BUY"}
                  />
                  <input
                    type="radio"
                    name="order[side]"
                    value="SELL"
                    class="join-item btn flex-1"
                    aria-label="SELL"
                    checked={@new_order_form["side"] == "SELL"}
                  />
                </div>
              </div>

              <!-- Order Type -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Order Type *</span>
                </label>
                <select name="order[type]" class="select select-bordered w-full">
                  <option value="LIMIT" selected={@new_order_form["type"] == "LIMIT"}>
                    Limit
                  </option>
                  <option value="MARKET" selected={@new_order_form["type"] == "MARKET"}>
                    Market
                  </option>
                  <option
                    value="STOP_LOSS_LIMIT"
                    selected={@new_order_form["type"] == "STOP_LOSS_LIMIT"}
                  >
                    Stop Loss Limit
                  </option>
                  <option
                    value="TAKE_PROFIT_LIMIT"
                    selected={@new_order_form["type"] == "TAKE_PROFIT_LIMIT"}
                  >
                    Take Profit Limit
                  </option>
                </select>
              </div>

              <!-- Price (for Limit orders) -->
              <%= if @new_order_form["type"] != "MARKET" do %>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Price *</span>
                  </label>
                  <input
                    type="text"
                    name="order[price]"
                    value={@new_order_form["price"]}
                    placeholder="0.00"
                    class="input input-bordered w-full font-mono"
                    inputmode="decimal"
                  />
                </div>
              <% end %>

              <!-- Quantity -->
              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Quantity *</span>
                </label>
                <input
                  type="text"
                  name="order[quantity]"
                  value={@new_order_form["quantity"]}
                  placeholder="0.00"
                  class="input input-bordered w-full font-mono"
                  inputmode="decimal"
                />
              </div>

              <!-- Time in Force (for Limit orders) -->
              <%= if @new_order_form["type"] != "MARKET" do %>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Time in Force</span>
                  </label>
                  <select name="order[time_in_force]" class="select select-bordered w-full">
                    <option value="GTC" selected={@new_order_form["time_in_force"] == "GTC"}>
                      GTC (Good Till Cancelled)
                    </option>
                    <option value="IOC" selected={@new_order_form["time_in_force"] == "IOC"}>
                      IOC (Immediate or Cancel)
                    </option>
                    <option value="FOK" selected={@new_order_form["time_in_force"] == "FOK"}>
                      FOK (Fill or Kill)
                    </option>
                  </select>
                </div>
              <% end %>

              <!-- Order Summary -->
              <%= if @new_order_form["symbol"] != "" and @new_order_form["quantity"] != "" do %>
                <div class="alert alert-info">
                  <div>
                    <span class="font-medium">Order Summary:</span>
                    <span class={[
                      "badge ml-2",
                      if(@new_order_form["side"] == "BUY", do: "badge-success", else: "badge-error")
                    ]}>
                      <%= @new_order_form["side"] %>
                    </span>
                    <span class="ml-2">
                      <%= @new_order_form["quantity"] %> <%= @new_order_form["symbol"] %>
                    </span>
                    <%= if @new_order_form["type"] != "MARKET" and @new_order_form["price"] != "" do %>
                      <span class="ml-1">@ <%= @new_order_form["price"] %></span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Actions -->
              <div class="modal-action">
                <button
                  type="button"
                  class="btn btn-ghost"
                  phx-click="close_new_order_modal"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class={[
                    "btn",
                    if(@new_order_form["side"] == "BUY", do: "btn-success", else: "btn-error")
                  ]}
                  disabled={@creating_order}
                >
                  <%= if @creating_order do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% end %>
                  Place <%= @new_order_form["side"] %> Order
                </button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="close_new_order_modal"></div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp load_orders(socket) do
    case get_credentials() do
      {api_key, secret_key} ->
        case BinanceClient.get_open_orders(api_key, secret_key, nil) do
          {:ok, orders} ->
            # Sort by time descending
            sorted_orders = Enum.sort_by(orders, & &1["time"], :desc)

            # Group by symbol
            grouped = Enum.group_by(sorted_orders, & &1["symbol"])

            # Get unique symbols sorted
            symbols =
              grouped
              |> Map.keys()
              |> Enum.sort()

            socket
            |> assign(orders: sorted_orders)
            |> assign(grouped_orders: grouped)
            |> assign(available_symbols: symbols)
            |> assign(loading: false)
            |> assign(error: nil)

          {:error, reason} ->
            Logger.error("Failed to load open orders: #{inspect(reason)}")

            socket
            |> assign(loading: false)
            |> assign(error: "Failed to load orders: #{inspect(reason)}")
        end

      nil ->
        socket
        |> assign(loading: false)
        |> assign(error: "API credentials not configured")
    end
  end

  defp get_credentials do
    CredentialHelper.get_credentials(nil)
  end

  defp filtered_orders(orders, _grouped_orders, "all"), do: orders

  defp filtered_orders(_orders, grouped_orders, symbol) do
    Map.get(grouped_orders, symbol, [])
  end

  defp count_by_side(orders, side) do
    Enum.count(orders, &(&1["side"] == side))
  end

  defp format_timestamp(timestamp_ms) when is_integer(timestamp_ms) do
    timestamp_ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%m-%d %H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

  defp calculate_total_trim(price, qty) when is_binary(price) and is_binary(qty) do
    with {p, _} <- Decimal.parse(price),
         {q, _} <- Decimal.parse(qty) do
      total = Decimal.mult(p, q)
      trim_zeros(Decimal.round(total, 2)) <> " USDT"
    else
      _ -> "-"
    end
  end

  defp calculate_total_trim(_, _), do: "-"

  # Format number without trailing zeros
  defp format_number_trim(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> trim_zeros(decimal)
      :error -> value
    end
  end

  defp format_number_trim(_), do: "-"

  defp trim_zeros(decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  # New order helpers
  defp load_symbols(socket) do
    case BinanceClient.get_exchange_info() do
      {:ok, info} ->
        symbols =
          info["symbols"]
          |> Enum.filter(&(&1["status"] == "TRADING"))
          |> Enum.map(& &1["symbol"])
          |> Enum.sort()

        assign(socket, all_symbols: symbols)

      {:error, _reason} ->
        # Fallback to common symbols
        assign(socket, all_symbols: ["BTCUSDT", "ETHUSDT", "BNBUSDT", "XRPUSDT", "SOLUSDT"])
    end
  end

  defp default_order_form do
    %{
      "symbol" => "",
      "side" => "BUY",
      "type" => "LIMIT",
      "quantity" => "",
      "price" => "",
      "time_in_force" => "GTC"
    }
  end

  defp validate_order_form(form) do
    cond do
      form["symbol"] == "" ->
        {:error, "Symbol is required"}

      form["quantity"] == "" ->
        {:error, "Quantity is required"}

      form["type"] == "LIMIT" and form["price"] == "" ->
        {:error, "Price is required for LIMIT orders"}

      true ->
        :ok
    end
  end

  defp build_order_params(form) do
    base = %{
      symbol: form["symbol"],
      side: form["side"],
      type: form["type"],
      quantity: form["quantity"]
    }

    case form["type"] do
      "LIMIT" ->
        Map.merge(base, %{
          price: form["price"],
          timeInForce: form["time_in_force"]
        })

      "MARKET" ->
        base

      "STOP_LOSS_LIMIT" ->
        Map.merge(base, %{
          price: form["price"],
          stopPrice: form["stop_price"] || form["price"],
          timeInForce: form["time_in_force"]
        })

      "TAKE_PROFIT_LIMIT" ->
        Map.merge(base, %{
          price: form["price"],
          stopPrice: form["stop_price"] || form["price"],
          timeInForce: form["time_in_force"]
        })

      _ ->
        base
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(%{"msg" => msg}), do: msg
  defp format_error(reason), do: inspect(reason)
end
