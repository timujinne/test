defmodule DashboardWeb.HistoryLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.CredentialHelper
  alias DashboardWeb.Live.UserContext

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 30 seconds (not 10 - too aggressive)
      :timer.send_interval(30_000, self(), :refresh_history)
    end

    # Load symbols from orders DB + common symbols
    db_symbols = load_symbols_from_db()
    common_symbols = ["BTCUSDT", "ETHUSDT", "DOGEUSDT", "SOLUSDT", "DOTUSDT", "BNBUSDT"]
    available_symbols = (db_symbols ++ common_symbols) |> Enum.uniq() |> Enum.sort()

    # Default to first symbol, not ALL (faster loading)
    default_symbol = List.first(db_symbols, List.first(common_symbols, "BTCUSDT"))

    socket =
      socket
      |> UserContext.assign_user_context()
      |> assign(page_title: "History")
      |> assign(current_path: "/app/history")
      |> assign(orders: [])
      |> assign(trades: [])
      |> assign(available_symbols: available_symbols)
      |> assign(filter_symbol: default_symbol)
      |> assign(loading: false)
      |> assign(error: nil)
      |> load_history()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_symbol", %{"symbol" => symbol}, socket) do
    Logger.info("Symbol filter changed to: #{symbol}")
    {:noreply, socket |> assign(filter_symbol: symbol) |> load_history()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(loading: true) |> load_history()}
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
      <!-- Filter -->
      <div class="card bg-base-100 shadow-xl p-4">
        <div class="flex items-center gap-4">
          <label for="symbol-select" class="text-sm font-medium text-base-content whitespace-nowrap">
            Symbol:
          </label>
          <form phx-change="select_symbol">
            <select
              id="symbol-select"
              name="symbol"
              class="select select-bordered select-sm w-48"
            >
              <%= for symbol <- @available_symbols do %>
                <option value={symbol} selected={@filter_symbol == symbol}>
                  <%= symbol %>
                </option>
              <% end %>
              <option value="ALL" selected={@filter_symbol == "ALL"}>
                All (slow)
              </option>
            </select>
          </form>
          <span class="text-sm text-base-content/50">
            Showing: <span class="font-medium text-base-content"><%= @filter_symbol %></span>
          </span>
        </div>
        <%= if @loading do %>
          <div class="flex items-center justify-center mt-4">
            <span class="loading loading-spinner loading-md mr-2"></span>
            <span class="text-sm text-base-content/70">Loading history...</span>
          </div>
        <% end %>
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
                <%= if @filter_symbol == "ALL" do %>
                  No orders found in your history
                <% else %>
                  No orders found for <%= @filter_symbol %>
                <% end %>
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
                    <td class="text-right text-base-content font-mono">
                      <%= format_order_price_trim(order) %>
                    </td>
                    <td class="text-right text-base-content font-mono">
                      <%= format_number_trim(order["origQty"]) %>
                    </td>
                    <td class="text-right text-base-content font-mono">
                      <%= format_number_trim(order["executedQty"]) %>
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
                  <th class="text-left">Type</th>
                  <th class="text-right">Price</th>
                  <th class="text-right">Quantity</th>
                  <th class="text-right">Quote Qty</th>
                  <th class="text-right">Commission</th>
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
                    <td>
                      <%= if trade["isMaker"] do %>
                        <span class="badge badge-sm badge-info">MAKER</span>
                      <% else %>
                        <span class="badge badge-sm badge-ghost">TAKER</span>
                      <% end %>
                    </td>
                    <td class="text-right text-base-content font-mono">
                      <%= format_number_trim(trade["price"]) %>
                    </td>
                    <td class="text-right text-base-content font-mono">
                      <%= format_number_trim(trade["qty"]) %>
                    </td>
                    <td class="text-right text-base-content font-mono">
                      <%= format_number_trim(trade["quoteQty"]) %>
                    </td>
                    <td class="text-right text-base-content/70 font-mono">
                      <%= format_number_trim(trade["commission"]) %> <%= trade["commissionAsset"] %>
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
          error:
            "Binance API credentials not configured. Please set BINANCE_API_KEY and BINANCE_SECRET_KEY.",
          orders: [],
          trades: []
        )
    end
  end

  defp load_orders_and_trades(socket, api_key, secret_key, "ALL") do
    # For "ALL", load only from top 3 symbols to avoid slow loading
    symbols = socket.assigns.available_symbols |> Enum.take(3)

    # Load orders from limited symbols (20 each max)
    all_orders =
      symbols
      |> Enum.flat_map(fn sym ->
        case DataCollector.BinanceClient.get_all_orders(api_key, secret_key, sym, limit: 20) do
          {:ok, orders_list} -> orders_list
          {:error, _} -> []
        end
      end)
      |> Enum.sort_by(& &1["time"], :desc)
      |> Enum.take(50)

    # Load trades from limited symbols
    all_trades =
      symbols
      |> Enum.flat_map(fn sym ->
        case DataCollector.BinanceClient.get_my_trades(api_key, secret_key, sym, limit: 20) do
          {:ok, trades_list} -> trades_list
          {:error, _} -> []
        end
      end)
      |> Enum.sort_by(& &1["time"], :desc)
      |> Enum.take(50)

    socket
    |> assign(loading: false, orders: all_orders, trades: all_trades)
  end

  defp load_orders_and_trades(socket, api_key, secret_key, symbol) do
    # Load orders for specific symbol
    orders =
      case DataCollector.BinanceClient.get_all_orders(api_key, secret_key, symbol, limit: 100) do
        {:ok, orders_list} ->
          # Sort by time descending
          Enum.sort_by(orders_list, & &1["time"], :desc)

        {:error, reason} ->
          Logger.error("Failed to load orders: #{inspect(reason)}")
          []
      end

    # Load trades for specific symbol
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

  defp format_order_price_trim(order) do
    price = order["price"]

    case Decimal.parse(price || "0") do
      {decimal, _} ->
        if Decimal.eq?(decimal, Decimal.new(0)) do
          # Market order - calculate average price from executed amounts
          calculate_avg_price_trim(order["cummulativeQuoteQty"], order["executedQty"])
        else
          trim_zeros(decimal)
        end

      :error ->
        "-"
    end
  end

  defp calculate_avg_price_trim(quote_qty, exec_qty)
       when is_binary(quote_qty) and is_binary(exec_qty) do
    with {quote_dec, _} <- Decimal.parse(quote_qty),
         {exec_dec, _} <- Decimal.parse(exec_qty),
         false <- Decimal.eq?(exec_dec, Decimal.new(0)) do
      avg = Decimal.div(quote_dec, exec_dec)
      trim_zeros(Decimal.round(avg, 2))
    else
      _ -> "-"
    end
  end

  defp calculate_avg_price_trim(_, _), do: "-"

  # Format number without trailing zeros
  defp format_number_trim(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> trim_zeros(decimal)
      :error -> value
    end
  end

  defp format_number_trim(value) when is_number(value) do
    value |> Decimal.from_float() |> trim_zeros()
  end

  defp format_number_trim(_), do: "-"

  defp trim_zeros(decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  # Load unique symbols from orders and trades tables
  defp load_symbols_from_db do
    import Ecto.Query

    # Get symbols from orders
    order_symbols = SharedData.Repo.all(
      from o in "orders",
      distinct: o.symbol,
      select: o.symbol
    ) || []

    # Get symbols from trades
    trade_symbols = SharedData.Repo.all(
      from t in "trades",
      distinct: t.symbol,
      select: t.symbol
    ) || []

    # Combine and sort
    (order_symbols ++ trade_symbols)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
