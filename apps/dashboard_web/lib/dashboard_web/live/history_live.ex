defmodule DashboardWeb.HistoryLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.{DecimalHelper, CredentialHelper}

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Phase 8: Will get account_id from authenticated session
    # For now, use testnet credentials from environment

    if connected?(socket) do
      # Schedule periodic refresh every 10 seconds
      :timer.send_interval(10_000, self(), :refresh_history)
    end

    socket =
      socket
      |> assign(page_title: "History")
      |> assign(current_path: "/history")
      |> assign(orders: [])
      |> assign(trades: [])
      |> assign(filter_symbol: "BTCUSDT")
      |> assign(loading: false)
      |> assign(error: nil)
      |> load_history()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_symbol", %{"symbol" => symbol}, socket) do
    filter = if symbol == "", do: "BTCUSDT", else: String.upcase(symbol)
    {:noreply, socket |> assign(filter_symbol: filter) |> load_history()}
  end

  @impl true
  def handle_info(:refresh_history, socket) do
    {:noreply, load_history(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-base-content">Order History</h1>
          <p class="mt-2 text-sm text-base-content/70">
            View your past orders and trades from Binance
          </p>
        </div>
      </div>

      <!-- Filters -->
      <div class="card bg-base-100 shadow-xl p-4">
        <div class="flex items-center space-x-4">
          <div class="flex-1">
            <label for="symbol-filter" class="block text-sm font-medium text-base-content">
              Filter by Symbol
            </label>
            <input
              type="text"
              id="symbol-filter"
              phx-change="filter_symbol"
              name="symbol"
              value={@filter_symbol}
              placeholder="e.g. BTCUSDT"
              class="input input-bordered w-full mt-1"
            />
          </div>
          <%= if @loading do %>
            <div class="text-sm text-base-content/70">
              <span class="loading loading-spinner loading-sm"></span>
              Loading...
            </div>
          <% end %>
        </div>
        <%= if @error do %>
          <div class="alert alert-error mt-4">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span><%= @error %></span>
          </div>
        <% end %>
      </div>

      <!-- Orders Table -->
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">All Orders</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@orders) do %>
            <div class="px-6 py-12 text-center">
              <svg
                class="mx-auto h-12 w-12 text-base-content/40"
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
              <h3 class="mt-2 text-sm font-medium text-base-content">No orders</h3>
              <p class="mt-1 text-sm text-base-content/70">
                No orders found for <%= @filter_symbol %>
              </p>
            </div>
          <% else %>
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left">Date/Time</th>
                  <th class="text-left">Order ID</th>
                  <th class="text-left">Symbol</th>
                  <th class="text-left">Side</th>
                  <th class="text-left">Type</th>
                  <th class="text-right">Price</th>
                  <th class="text-right">Quantity</th>
                  <th class="text-right">Filled</th>
                  <th class="text-left">Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for order <- @orders do %>
                  <tr>
                    <td class="text-base-content">
                      <%= format_timestamp(order["time"]) %>
                    </td>
                    <td class="text-base-content/70 font-mono text-xs">
                      <%= order["orderId"] %>
                    </td>
                    <td>
                      <span class="font-medium text-base-content">
                        <%= order["symbol"] %>
                      </span>
                    </td>
                    <td>
                      <span class={[
                        "badge",
                        if(order["side"] == "BUY", do: "badge-success", else: "badge-error")
                      ]}>
                        <%= order["side"] %>
                      </span>
                    </td>
                    <td class="text-base-content/70">
                      <%= order["type"] %>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_price(order["price"]) %>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_quantity(order["origQty"]) %>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_quantity(order["executedQty"]) %>
                    </td>
                    <td>
                      <span class={[
                        "badge",
                        case order["status"] do
                          "FILLED" -> "badge-success"
                          "NEW" -> "badge-info"
                          "PARTIALLY_FILLED" -> "badge-warning"
                          "CANCELED" -> "badge-ghost"
                          "REJECTED" -> "badge-error"
                          "EXPIRED" -> "badge-ghost"
                          _ -> "badge-ghost"
                        end
                      ]}>
                        <%= order["status"] %>
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <!-- Trades Table -->
      <%= if not Enum.empty?(@trades) do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="px-6 py-4 border-b border-base-300">
            <h2 class="text-xl font-semibold text-base-content">Executed Trades</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left">Date/Time</th>
                  <th class="text-left">Trade ID</th>
                  <th class="text-left">Order ID</th>
                  <th class="text-left">Symbol</th>
                  <th class="text-left">Side</th>
                  <th class="text-right">Price</th>
                  <th class="text-right">Quantity</th>
                  <th class="text-right">Quote Qty</th>
                  <th class="text-right">Commission</th>
                  <th class="text-left">Maker</th>
                </tr>
              </thead>
              <tbody>
                <%= for trade <- @trades do %>
                  <tr>
                    <td class="text-base-content">
                      <%= format_timestamp(trade["time"]) %>
                    </td>
                    <td class="text-base-content/70 font-mono text-xs">
                      <%= trade["id"] %>
                    </td>
                    <td class="text-base-content/70 font-mono text-xs">
                      <%= trade["orderId"] %>
                    </td>
                    <td>
                      <span class="font-medium text-base-content">
                        <%= trade["symbol"] %>
                      </span>
                    </td>
                    <td>
                      <span class={[
                        "badge",
                        if(trade["isBuyer"], do: "badge-success", else: "badge-error")
                      ]}>
                        <%= if trade["isBuyer"], do: "BUY", else: "SELL" %>
                      </span>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_price(trade["price"]) %>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_quantity(trade["qty"]) %>
                    </td>
                    <td class="text-right text-base-content">
                      <%= format_price(trade["quoteQty"]) %>
                    </td>
                    <td class="text-right text-base-content/70">
                      <%= format_quantity(trade["commission"]) %>
                      <%= trade["commissionAsset"] %>
                    </td>
                    <td>
                      <%= if trade["isMaker"] do %>
                        <span class="badge badge-sm badge-info">MAKER</span>
                      <% else %>
                        <span class="badge badge-sm badge-ghost">TAKER</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp load_history(socket) do
    symbol = socket.assigns.filter_symbol

    case get_testnet_credentials() do
      {api_key, secret_key} ->
        socket
        |> assign(loading: true, error: nil)
        |> load_orders_and_trades(api_key, secret_key, symbol)

      nil ->
        socket
        |> assign(
          loading: false,
          error: "Binance API credentials not configured. Please set BINANCE_API_KEY and BINANCE_SECRET_KEY.",
          orders: [],
          trades: []
        )
    end
  end

  defp load_orders_and_trades(socket, api_key, secret_key, symbol) do
    # Load orders
    orders =
      case DataCollector.BinanceClient.get_all_orders(api_key, secret_key, symbol, limit: 100) do
        {:ok, orders_list} ->
          # Sort by time descending
          Enum.sort_by(orders_list, & &1["time"], :desc)

        {:error, reason} ->
          Logger.error("Failed to load orders: #{inspect(reason)}")
          []
      end

    # Load trades
    trades =
      case DataCollector.BinanceClient.get_my_trades(api_key, secret_key, symbol, limit: 100) do
        {:ok, trades_list} ->
          # Sort by time descending
          Enum.sort_by(trades_list, & &1["time"], :desc)

        {:error, reason} ->
          Logger.error("Failed to load trades: #{inspect(reason)}")
          []
      end

    socket
    |> assign(loading: false, orders: orders, trades: trades)
  end

  defp get_testnet_credentials do
    # Try to get credentials from database (for authenticated user) or fallback to env vars
    # Phase 8: Will pass actual user_id from authenticated session
    user_id = nil
    CredentialHelper.get_credentials(user_id)
  end

  defp format_timestamp(timestamp_ms) when is_integer(timestamp_ms) do
    timestamp_ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(timestamp_str) when is_binary(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {timestamp_ms, _} -> format_timestamp(timestamp_ms)
      :error -> timestamp_str
    end
  end

  defp format_timestamp(_), do: "-"

  defp format_price(price) when is_binary(price) do
    case Decimal.parse(price) do
      {decimal, _} ->
        if Decimal.eq?(decimal, Decimal.new(0)) do
          "Market"
        else
          DecimalHelper.format(decimal, 8)
        end

      :error ->
        price
    end
  end

  defp format_price(price) when is_number(price) do
    format_price(to_string(price))
  end

  defp format_price(_), do: "-"

  defp format_quantity(qty) when is_binary(qty) do
    case Decimal.parse(qty) do
      {decimal, _} -> DecimalHelper.format(decimal, 8)
      :error -> qty
    end
  end

  defp format_quantity(qty) when is_number(qty) do
    format_quantity(to_string(qty))
  end

  defp format_quantity(_), do: "-"
end
