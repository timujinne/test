defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.DecimalHelper
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # Note: User authentication will be added in Phase 8
    # For now, account_id should be passed via session or params

    if connected?(socket) do
      # Subscribe to market and order updates
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")

      # Load balances and prices
      send(self(), :load_balances)
      send(self(), :load_prices)
    end

    socket =
      socket
      |> assign(page_title: "Trading")
      |> assign(current_path: "/trading")
      |> assign(active_orders: [])
      |> assign(recent_trades: [])
      |> assign(current_price: nil)
      |> assign(account_id: nil)
      |> assign(balances: [])
      |> assign(prices: %{})
      |> assign(order_form: %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "", "price" => ""})
      |> assign(order_result: nil)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:execution_report, _data}, socket) do
    # Reload orders when execution report received
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:ticker, %{"c" => price}}, socket) do
    {:noreply, assign(socket, current_price: Decimal.new(price))}
  end

  @impl true
  def handle_info(:load_balances, socket) do
    balances =
      case get_testnet_credentials() do
        {api_key, secret_key} ->
          case DataCollector.BinanceClient.get_balances(api_key, secret_key) do
            {:ok, all_balances} ->
              all_balances
              |> Enum.filter(fn %{"free" => free} ->
                {val, _} = Decimal.parse(free)
                Decimal.gt?(val, Decimal.new(0))
              end)
              |> Enum.take(10)

            _ ->
              []
          end

        nil ->
          []
      end

    {:noreply, assign(socket, balances: balances)}
  end

  @impl true
  def handle_info(:load_prices, socket) do
    symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT"]

    prices =
      symbols
      |> Enum.map(fn symbol ->
        case DataCollector.BinanceClient.get_ticker_price(symbol) do
          {:ok, %{"price" => price}} -> {symbol, price}
          _ -> {symbol, nil}
        end
      end)
      |> Map.new()

    {:noreply, assign(socket, prices: prices)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_form", %{"order" => params}, socket) do
    {:noreply, assign(socket, order_form: params)}
  end

  @impl true
  def handle_event("create_order", %{"order" => params}, socket) do
    case get_testnet_credentials() do
      {api_key, secret_key} ->
        order_params = %{
          symbol: params["symbol"],
          side: params["side"],
          type: params["type"],
          quantity: params["quantity"],
          price: params["price"],
          timeInForce: "GTC"
        }

        case DataCollector.BinanceClient.create_order(api_key, secret_key, order_params) do
          {:ok, result} ->
            socket =
              socket
              |> put_flash(:info, "Order created successfully! Order ID: #{result["orderId"]}")
              |> assign(order_result: result)
              |> assign(order_form: %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "LIMIT", "quantity" => "", "price" => ""})

            send(self(), :load_balances)
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create order: #{inspect(reason)}")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "Testnet credentials not configured")}
    end
  end

  @impl true
  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    case cancel_order(order_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Order cancelled successfully")
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel order: #{reason}")}
    end
  end

  defp cancel_order(order_id) do
    with {:ok, order} <- get_order_with_credentials(order_id),
         {:ok, _result} <- execute_cancel(order) do
      # Update order status in database
      order
      |> Order.changeset(%{status: "CANCELED"})
      |> Repo.update()
    end
  end

  defp get_order_with_credentials(order_id) do
    query =
      from o in Order,
        where: o.id == ^order_id,
        preload: [account: :api_credential]

    case Repo.one(query) do
      nil -> {:error, "Order not found"}
      order -> {:ok, order}
    end
  end

  defp execute_cancel(%{account: %{api_credential: nil}}) do
    {:error, "No API credentials configured"}
  end

  defp execute_cancel(%{order_id: nil}) do
    {:error, "Order has no Binance order ID"}
  end

  defp execute_cancel(%{
         order_id: binance_order_id,
         symbol: symbol,
         account: %{api_credential: cred}
       }) do
    DataCollector.BinanceClient.cancel_order(
      cred.api_key,
      cred.secret_key,
      symbol,
      binance_order_id
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-3xl font-bold text-gray-900">Binance Testnet Trading</h1>
        <%= if @current_price do %>
          <div class="text-right">
            <div class="text-sm text-gray-500">BTC/USDT</div>
            <div class="text-2xl font-bold text-gray-900">
              <%= DecimalHelper.format(@current_price, 2) %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Market Prices -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <%= for {symbol, price} <- @prices do %>
          <div class="bg-white shadow rounded-lg p-4">
            <div class="text-sm text-gray-500"><%= symbol %></div>
            <div class="text-xl font-bold text-gray-900">
              <%= if price, do: "$#{price}", else: "Loading..." %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Testnet Balances -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Testnet Balances</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@balances) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              Loading balances...
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Asset</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Free</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Locked</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for balance <- @balances do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= balance["asset"] %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= balance["free"] %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 text-right">
                      <%= balance["locked"] %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <!-- Order Creation Form -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Create Test Order</h2>
        </div>
        <div class="px-6 py-4">
          <form phx-change="update_form" phx-submit="create_order">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700">Symbol</label>
                <select name="order[symbol]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
                  <option value="BTCUSDT" selected={@order_form["symbol"] == "BTCUSDT"}>BTC/USDT</option>
                  <option value="ETHUSDT" selected={@order_form["symbol"] == "ETHUSDT"}>ETH/USDT</option>
                  <option value="BNBUSDT" selected={@order_form["symbol"] == "BNBUSDT"}>BNB/USDT</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700">Side</label>
                <select name="order[side]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
                  <option value="BUY" selected={@order_form["side"] == "BUY"}>BUY</option>
                  <option value="SELL" selected={@order_form["side"] == "SELL"}>SELL</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700">Type</label>
                <select name="order[type]" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
                  <option value="LIMIT" selected={@order_form["type"] == "LIMIT"}>LIMIT</option>
                  <option value="MARKET" selected={@order_form["type"] == "MARKET"}>MARKET</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700">Quantity</label>
                <input type="text" name="order[quantity]" value={@order_form["quantity"]}
                       class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                       placeholder="0.001" />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700">Price (LIMIT only)</label>
                <input type="text" name="order[price]" value={@order_form["price"]}
                       class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                       placeholder="50000" />
              </div>
            </div>
            <div class="mt-4">
              <button type="submit" class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700">
                Create Order
              </button>
            </div>
          </form>

          <%= if @order_result do %>
            <div class="mt-4 p-4 bg-green-50 rounded-md">
              <div class="text-sm font-medium text-green-800">
                Order Created Successfully!
              </div>
              <div class="text-xs text-green-700 mt-2">
                Order ID: <%= @order_result["orderId"] %> |
                Status: <%= @order_result["status"] %> |
                Symbol: <%= @order_result["symbol"] %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Active Orders -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Active Orders</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@active_orders) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              No active orders
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Symbol</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Side</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Price</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Quantity</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Filled</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for order <- @active_orders do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= order.symbol %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= order.type %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        if(order.side == "BUY", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                      ]}>
                        <%= order.side %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= if order.price, do: DecimalHelper.format(order.price, 2), else: "MARKET" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(order.quantity, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(order.filled_qty, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class="px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                        <%= order.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <button
                        phx-click="cancel_order"
                        phx-value-id={order.id}
                        class="text-red-600 hover:text-red-900"
                      >
                        Cancel
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>

      <!-- Recent Trades -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Recent Trades</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@recent_trades) do %>
            <div class="px-6 py-8 text-center text-gray-500">
              No recent trades
            </div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Symbol</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Side</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Price</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Quantity</th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for trade <- @recent_trades do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= Calendar.strftime(trade.timestamp, "%H:%M:%S") %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= trade.symbol %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm">
                      <span class={[
                        "px-2 py-1 rounded-full text-xs font-medium",
                        if(trade.side == "BUY", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                      ]}>
                        <%= trade.side %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.price, 2) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= DecimalHelper.format(trade.quantity, 6) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
                      <%= if trade.pnl do %>
                        <span class={[
                          "font-medium",
                          if(DecimalHelper.positive?(trade.pnl), do: "text-green-600", else: "text-red-600")
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
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp get_testnet_credentials do
    api_key = System.get_env("BINANCE_API_KEY")
    secret_key = System.get_env("BINANCE_SECRET_KEY")

    if api_key && secret_key do
      {api_key, secret_key}
    else
      nil
    end
  end

  defp load_data(socket) do
    # Phase 8: Will load data based on authenticated user's account
    # Currently returns empty data until user authentication is implemented
    socket
    |> assign(active_orders: load_active_orders(socket.assigns.account_id))
    |> assign(recent_trades: load_recent_trades(socket.assigns.account_id))
  end

  defp load_active_orders(nil), do: []

  defp load_active_orders(account_id) do
    query =
      from o in Order,
        where: o.account_id == ^account_id,
        where: o.status in ["NEW", "PARTIALLY_FILLED"],
        order_by: [desc: o.inserted_at],
        limit: 50

    Repo.all(query)
  end

  defp load_recent_trades(nil), do: []

  defp load_recent_trades(account_id) do
    alias SharedData.Schemas.Trade

    query =
      from t in Trade,
        where: t.account_id == ^account_id,
        order_by: [desc: t.timestamp],
        limit: 20

    Repo.all(query)
  end
end
