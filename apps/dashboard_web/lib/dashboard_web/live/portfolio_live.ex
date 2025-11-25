defmodule DashboardWeb.PortfolioLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.DecimalHelper
  alias SharedData.Repo
  alias SharedData.Schemas.Balance

  import Ecto.Query

  # Stablecoins that are 1:1 with USD
  @stablecoins ~w(USDT USDC BUSD TUSD DAI FDUSD)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "balance_updates")
      # Subscribe to price updates for common pairs
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:ETHUSDT")
    end

    socket =
      socket
      |> assign(page_title: "Portfolio")
      |> assign(current_path: "/portfolio")
      |> assign(balances: [])
      |> assign(total_value: Decimal.new(0))
      |> assign(total_pnl: Decimal.new(0))
      |> assign(account_id: nil)
      |> assign(prices: %{})
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:balance_update, _data}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:ticker, %{"s" => symbol, "c" => price}}, socket) do
    # Update prices map when we receive ticker updates
    prices = Map.put(socket.assigns.prices, symbol, Decimal.new(price))
    {:noreply, assign(socket, prices: prices) |> recalculate_total_value()}
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
    # Phase 8: Will load data based on authenticated user's account
    account_id = socket.assigns.account_id
    balances = load_balances(account_id)
    prices = load_current_prices(balances)
    total_value = calculate_total_value(balances, prices)
    total_pnl = calculate_total_pnl(account_id)

    socket
    |> assign(balances: balances)
    |> assign(prices: prices)
    |> assign(total_value: total_value)
    |> assign(total_pnl: total_pnl)
  end

  defp load_balances(nil), do: []

  defp load_balances(account_id) do
    query =
      from b in Balance,
        where: b.account_id == ^account_id,
        order_by: [desc: b.updated_at]

    Repo.all(query)
    |> Enum.map(fn balance ->
      total = Decimal.add(balance.free || Decimal.new(0), balance.locked || Decimal.new(0))
      Map.put(balance, :total, total)
    end)
  end

  defp load_current_prices(balances) do
    # Get unique assets that need price lookup
    assets =
      balances
      |> Enum.map(& &1.asset)
      |> Enum.reject(&(&1 in @stablecoins))
      |> Enum.uniq()

    # Try to get prices from MarketData cache or fetch from API
    Enum.reduce(assets, %{}, fn asset, acc ->
      symbol = "#{asset}USDT"

      case DataCollector.MarketData.get_price(symbol) do
        {:ok, price} -> Map.put(acc, symbol, price)
        {:error, _} -> acc
      end
    end)
  end

  defp calculate_total_value(balances, prices) do
    Enum.reduce(balances, Decimal.new(0), fn balance, acc ->
      value = calculate_asset_value(balance, prices)
      Decimal.add(acc, value)
    end)
  end

  defp calculate_asset_value(%{asset: asset, total: total}, _prices) when asset in @stablecoins do
    total
  end

  defp calculate_asset_value(%{asset: asset, total: total}, prices) do
    symbol = "#{asset}USDT"

    case Map.get(prices, symbol) do
      nil -> Decimal.new(0)
      price -> Decimal.mult(total, price)
    end
  end

  defp calculate_total_pnl(nil), do: Decimal.new(0)

  defp calculate_total_pnl(account_id) do
    TradingEngine.RiskManager.calculate_daily_loss(account_id)
  end

  defp recalculate_total_value(socket) do
    total_value = calculate_total_value(socket.assigns.balances, socket.assigns.prices)
    assign(socket, total_value: total_value)
  end

  defp calculate_value(%{asset: asset, total: total}) when asset in @stablecoins do
    DecimalHelper.format_currency(total, "USDT", 2)
  end

  defp calculate_value(%{asset: asset, total: total} = _balance) do
    symbol = "#{asset}USDT"

    case DataCollector.MarketData.get_price(symbol) do
      {:ok, price} ->
        value = Decimal.mult(total, price)
        DecimalHelper.format_currency(value, "USDT", 2)

      {:error, _} ->
        "-"
    end
  end
end
