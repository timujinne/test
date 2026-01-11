defmodule DashboardWeb.PortfolioLive do
  use DashboardWeb, :live_view

  require Logger
  alias SharedData.Helpers.{DecimalHelper, CredentialHelper}
  alias DashboardWeb.Live.UserContext

  # Stablecoins that are 1:1 with USD
  @stablecoins ~w(USDT USDC BUSD TUSD DAI FDUSD)
  # Refresh every 30 seconds
  @refresh_interval_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "balance_updates")
      # Subscribe to price updates for assets we hold
      send(self(), :subscribe_to_prices)

      # Schedule periodic refresh every 30 seconds
      :timer.send_interval(@refresh_interval_ms, self(), :refresh_portfolio)

      # Initial load
      send(self(), :load_portfolio)
    end

    socket =
      socket
      |> UserContext.assign_user_context()
      |> assign(page_title: "Portfolio")
      |> assign(current_path: "/app/portfolio")
      |> assign(balances: [])
      |> assign(total_value: Decimal.new(0))
      |> assign(total_pnl: Decimal.new(0))
      |> assign(prices: %{})
      |> assign(loading: true)
      |> assign(error: nil)
      |> assign(last_updated: nil)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_portfolio, socket) do
    socket =
      socket
      |> load_balances_from_binance()
      |> load_prices_from_binance()
      |> calculate_portfolio_metrics()
      |> assign(loading: false)
      |> assign(last_updated: DateTime.utc_now())

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_portfolio, socket) do
    send(self(), :load_portfolio)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:subscribe_to_prices, socket) do
    # Will subscribe after we load balances
    {:noreply, socket}
  end

  @impl true
  def handle_info({:balance_update, _data}, socket) do
    send(self(), :load_portfolio)
    {:noreply, socket}
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
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold text-base-content">Portfolio Overview</h1>
          <p class="mt-2 text-sm text-base-content/70">
            Real-time balances from Binance Testnet
          </p>
        </div>
        <div class="text-sm text-base-content/60">
          <%= if @last_updated do %>
            Last updated: <%= Calendar.strftime(@last_updated, "%H:%M:%S") %>
          <% end %>
        </div>
      </div>

      <%= if @error do %>
        <div class="alert alert-error shadow-lg">
          <div>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current flex-shrink-0 h-6 w-6"
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
        </div>
      <% end %>

      <%= if @loading do %>
        <div class="flex justify-center items-center py-12">
          <span class="loading loading-spinner loading-lg"></span>
        </div>
      <% else %>
        <!-- Summary Cards -->
        <div class="stats stats-horizontal shadow w-full">
          <div class="stat">
            <div class="stat-title">Total Value</div>
            <div class="stat-value text-base-content">
              <%= DecimalHelper.format_currency(@total_value, "USDT", 2) %>
            </div>
            <div class="stat-desc">Across <%= length(@balances) %> assets</div>
          </div>

          <div class="stat">
            <div class="stat-title">Largest Holding</div>
            <div class="stat-value text-base-content">
              <%= get_largest_holding(@balances) %>
            </div>
            <div class="stat-desc">By value in USDT</div>
          </div>

          <div class="stat">
            <div class="stat-title">Assets</div>
            <div class="stat-value text-base-content">
              <%= length(@balances) %>
            </div>
            <div class="stat-desc">With non-zero balance</div>
          </div>
        </div>
        <!-- Portfolio Allocation -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Allocation Chart -->
          <div class="card bg-base-100 shadow-xl">
            <div class="px-6 py-4 border-b border-base-300">
              <h2 class="text-xl font-semibold text-base-content">Portfolio Allocation</h2>
            </div>
            <div class="px-6 py-6">
              <%= if Enum.empty?(@balances) do %>
                <div class="text-center text-base-content/70 py-8">
                  No assets found
                </div>
              <% else %>
                <div class="space-y-3">
                  <%= for balance <- Enum.take(@balances, 10) do %>
                    <div>
                      <div class="flex justify-between mb-1">
                        <span class="text-sm font-medium text-base-content">
                          <%= balance.asset %>
                        </span>
                        <span class="text-sm text-base-content/70">
                          <%= calculate_allocation_percentage(balance, @total_value) %>%
                        </span>
                      </div>
                      <div class="w-full bg-base-300 rounded-full h-2.5">
                        <div
                          class="bg-primary h-2.5 rounded-full"
                          style={"width: #{calculate_allocation_percentage(balance, @total_value)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Top Holdings -->
          <div class="card bg-base-100 shadow-xl">
            <div class="px-6 py-4 border-b border-base-300">
              <h2 class="text-xl font-semibold text-base-content">Top Holdings</h2>
            </div>
            <div class="px-6 py-4">
              <%= if Enum.empty?(@balances) do %>
                <div class="text-center text-base-content/70 py-8">
                  No assets found
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for balance <- Enum.take(@balances, 5) do %>
                    <div class="flex justify-between items-center">
                      <div>
                        <div class="font-semibold text-base-content"><%= balance.asset %></div>
                        <div class="text-sm text-base-content/60">
                          <%= DecimalHelper.format(balance.total, 8) %> <%= balance.asset %>
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="font-medium text-base-content">
                          <%= format_balance_value(balance) %>
                        </div>
                        <%= if balance.price do %>
                          <div class="text-sm text-base-content/60">
                            @ <%= DecimalHelper.format_currency(balance.price, "USDT", 2) %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        <!-- Balances Table -->
        <div class="card bg-base-100 shadow-xl">
          <div class="px-6 py-4 border-b border-base-300">
            <h2 class="text-xl font-semibold text-base-content">All Asset Balances</h2>
          </div>
          <div class="overflow-x-auto">
            <%= if Enum.empty?(@balances) do %>
              <div class="px-6 py-8 text-center text-base-content/70">
                No assets found. Make sure BINANCE_API_KEY and BINANCE_SECRET_KEY are configured.
              </div>
            <% else %>
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th class="text-left">Asset</th>
                    <th class="text-right">Free</th>
                    <th class="text-right">Locked</th>
                    <th class="text-right">Total</th>
                    <th class="text-right">Price (USDT)</th>
                    <th class="text-right">Value (USDT)</th>
                    <th class="text-right">Allocation</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for balance <- @balances do %>
                    <tr>
                      <td>
                        <div class="flex items-center">
                          <div class="text-sm font-medium text-base-content">
                            <%= balance.asset %>
                          </div>
                        </div>
                      </td>
                      <td class="text-right text-base-content">
                        <%= DecimalHelper.format(balance.free, 8) %>
                      </td>
                      <td class="text-right text-base-content">
                        <%= DecimalHelper.format(balance.locked, 8) %>
                      </td>
                      <td class="text-right font-medium text-base-content">
                        <%= DecimalHelper.format(balance.total, 8) %>
                      </td>
                      <td class="text-right text-base-content/70">
                        <%= format_price(balance) %>
                      </td>
                      <td class="text-right text-base-content font-medium">
                        <%= format_balance_value(balance) %>
                      </td>
                      <td class="text-right text-base-content/70">
                        <%= calculate_allocation_percentage(balance, @total_value) %>%
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp get_testnet_credentials do
    # Try to get credentials from database (for authenticated user) or fallback to env vars
    # Phase 8: Will pass actual user_id from authenticated session
    user_id = nil
    CredentialHelper.get_credentials(user_id)
  end

  defp load_balances_from_binance(socket) do
    case get_testnet_credentials() do
      {api_key, secret_key} ->
        case DataCollector.BinanceClient.get_balances(api_key, secret_key) do
          {:ok, binance_balances} ->
            balances =
              binance_balances
              |> Enum.map(fn balance ->
                free = parse_decimal(balance["free"])
                locked = parse_decimal(balance["locked"])
                total = Decimal.add(free, locked)

                %{
                  asset: balance["asset"],
                  free: free,
                  locked: locked,
                  total: total,
                  price: nil,
                  value: Decimal.new(0)
                }
              end)
              |> Enum.filter(fn b -> Decimal.gt?(b.total, 0) end)

            assign(socket, balances: balances, error: nil)

          {:error, reason} ->
            Logger.error("Failed to load balances: #{inspect(reason)}")

            assign(socket,
              balances: [],
              error: "Failed to load balances from Binance: #{inspect(reason)}"
            )
        end

      nil ->
        assign(socket,
          balances: [],
          error:
            "Testnet credentials not configured. Set BINANCE_API_KEY and BINANCE_SECRET_KEY environment variables."
        )
    end
  end

  defp load_prices_from_binance(socket) do
    balances = socket.assigns.balances

    if Enum.empty?(balances) do
      socket
    else
      # Fetch all ticker prices at once
      case get_testnet_credentials() do
        {_api_key, _secret_key} ->
          case DataCollector.BinanceClient.get_all_ticker_prices() do
            {:ok, ticker_prices} ->
              # Create a map of symbol => price
              price_map =
                ticker_prices
                |> Enum.map(fn %{"symbol" => symbol, "price" => price} ->
                  {symbol, parse_decimal(price)}
                end)
                |> Enum.into(%{})

              # Update balances with prices
              updated_balances =
                Enum.map(balances, fn balance ->
                  {price, value} =
                    get_asset_price_and_value(balance.asset, balance.total, price_map)

                  %{balance | price: price, value: value}
                end)
                |> Enum.sort_by(& &1.value, {:desc, Decimal})

              assign(socket, balances: updated_balances, prices: price_map)

            {:error, reason} ->
              Logger.warning("Failed to load prices: #{inspect(reason)}")
              socket
          end

        nil ->
          socket
      end
    end
  end

  defp get_asset_price_and_value(asset, total, _price_map) when asset in @stablecoins do
    # Stablecoins are 1:1 with USDT
    {Decimal.new(1), total}
  end

  defp get_asset_price_and_value(asset, total, price_map) do
    symbol = "#{asset}USDT"

    case Map.get(price_map, symbol) do
      nil ->
        {nil, Decimal.new(0)}

      price ->
        value = Decimal.mult(total, price)
        {price, value}
    end
  end

  defp calculate_portfolio_metrics(socket) do
    total_value =
      socket.assigns.balances
      |> Enum.reduce(Decimal.new(0), fn balance, acc ->
        Decimal.add(acc, balance.value)
      end)

    assign(socket, total_value: total_value)
  end

  defp recalculate_total_value(socket) do
    updated_balances =
      Enum.map(socket.assigns.balances, fn balance ->
        {price, value} =
          get_asset_price_and_value(balance.asset, balance.total, socket.assigns.prices)

        %{balance | price: price, value: value}
      end)
      |> Enum.sort_by(& &1.value, {:desc, Decimal})

    total_value =
      updated_balances
      |> Enum.reduce(Decimal.new(0), fn balance, acc ->
        Decimal.add(acc, balance.value)
      end)

    socket
    |> assign(balances: updated_balances)
    |> assign(total_value: total_value)
  end

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end

  defp parse_decimal(value) when is_number(value) do
    Decimal.from_float(value * 1.0)
  end

  defp parse_decimal(_), do: Decimal.new(0)

  defp get_largest_holding(balances) do
    case Enum.max_by(balances, & &1.value, fn -> nil end) do
      nil -> "-"
      balance -> balance.asset
    end
  end

  defp format_balance_value(%{asset: asset, value: value}) when asset in @stablecoins do
    DecimalHelper.format_currency(value, "USDT", 2)
  end

  defp format_balance_value(%{value: value}) do
    DecimalHelper.format_currency(value, "USDT", 2)
  end

  defp format_price(%{asset: asset}) when asset in @stablecoins do
    "1.00"
  end

  defp format_price(%{price: nil}), do: "-"

  defp format_price(%{price: price}) do
    DecimalHelper.format(price, 2)
  end

  defp calculate_allocation_percentage(_balance, total_value) when total_value == 0 do
    "0.00"
  end

  defp calculate_allocation_percentage(%{value: value}, total_value) do
    percentage =
      value
      |> Decimal.div(total_value)
      |> Decimal.mult(100)

    DecimalHelper.format(percentage, 2)
  end
end
