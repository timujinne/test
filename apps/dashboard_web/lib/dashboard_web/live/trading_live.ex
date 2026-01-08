defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view

  alias SharedData.Helpers.{DecimalHelper, CredentialHelper}
  alias SharedData.Repo
  alias SharedData.Schemas.Order

  # Import trading components
  alias DashboardWeb.Components.Trading.PriceChart
  alias DashboardWeb.Components.Trading.DepthChart

  import Ecto.Query

  @default_symbol "BTCUSDT"
  @default_interval "1h"
  @depth_throttle_ms 500  # Throttle order book updates to every 500ms

  @impl true
  def mount(_params, _session, socket) do
    # Note: User authentication will be added in Phase 8
    # For now, account_id should be passed via session or params

    if connected?(socket) do
      # Subscribe to market and order updates
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "order_updates")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "orders:all")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{@default_symbol}")

      # Subscribe to system status updates for streams
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "system:streams")

      # Subscribe to depth and kline streams
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "depth:#{@default_symbol}")
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "kline:#{@default_symbol}:#{@default_interval}")

      # Load balances and prices
      send(self(), :load_balances)
      send(self(), :load_prices)
      send(self(), :load_initial_chart_data)
      send(self(), :load_order_book)
      send(self(), :load_symbols)
      send(self(), :start_streams)
      send(self(), :load_open_orders)
      send(self(), :load_stream_status)

      # Schedule periodic order book refresh (every 1 sec)
      :timer.send_interval(1000, self(), :load_order_book)
    end

    socket =
      socket
      |> assign(page_title: "Trading")
      |> assign(current_path: "/app/trading")
      |> assign(active_orders: [])
      |> assign(recent_trades: [])
      |> assign(current_price: nil)
      |> assign(account_id: nil)
      |> assign(balances: [])
      |> assign(prices: %{})
      |> assign(symbol: @default_symbol)
      |> assign(interval: @default_interval)
      |> assign(order_book: %{bids: [], asks: []})
      |> assign(pending_depth: nil)
      |> assign(last_depth_update: 0)
      |> assign(symbol_search: "")
      |> assign(symbol_search_results: [])
      |> assign(show_symbol_dropdown: false)
      |> assign(available_symbols: [])
      |> assign(open_orders: [])
      |> assign(active_streams: [])
      |> assign(
        order_form: %{
          "symbol" => "BTCUSDT",
          "side" => "BUY",
          "type" => "LIMIT",
          "quantity" => "",
          "price" => ""
        }
      )
      |> assign(order_result: nil)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:execution_report, _data}, socket) do
    # Reload orders when execution report received
    socket = socket |> load_data() |> reload_open_orders()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:order_created, _order}, socket) do
    # Reload orders when a new order is created
    socket = socket |> load_data() |> reload_open_orders()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:order_filled, _execution}, socket) do
    # Reload orders and balances when order is filled
    socket = socket |> load_data() |> reload_open_orders()
    send(self(), :load_balances)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:order_cancelled, _execution}, socket) do
    # Reload orders when order is cancelled
    socket = socket |> load_data() |> reload_open_orders()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:order_partially_filled, _execution}, socket) do
    # Reload orders when order is partially filled
    socket = socket |> load_data() |> reload_open_orders()
    {:noreply, socket}
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
  def handle_info(:load_initial_chart_data, socket) do
    # Load historical klines for chart
    symbol = socket.assigns.symbol
    interval = socket.assigns.interval

    socket =
      case DataCollector.BinanceClient.get_klines(symbol, interval, limit: 100) do
        {:ok, klines} ->
          candles = Enum.map(klines, fn kline ->
            # Binance klines: [open_time, open, high, low, close, volume, close_time, ...]
            [open_time, open, high, low, close, volume | _rest] = kline
            %{
              time: open_time,
              open: parse_float(open),
              high: parse_float(high),
              low: parse_float(low),
              close: parse_float(close),
              volume: parse_float(volume)
            }
          end)

          push_event(socket, "price_chart_init", %{candles: candles})

        {:error, _reason} ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_symbols, socket) do
    # Load all USDT trading pairs
    symbols =
      case DataCollector.BinanceClient.get_exchange_info() do
        {:ok, %{"symbols" => symbols_data}} ->
          symbols_data
          |> Enum.filter(fn s ->
            s["status"] == "TRADING" and
            s["quoteAsset"] == "USDT" and
            s["isSpotTradingAllowed"] == true
          end)
          |> Enum.map(fn s -> s["symbol"] end)
          |> Enum.sort()

        {:error, _} ->
          # Fallback to common pairs
          ["BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT", "ADAUSDT"]
      end

    {:noreply, assign(socket, available_symbols: symbols)}
  end

  @impl true
  def handle_info(:load_order_book, socket) do
    # Load order book via REST API
    symbol = socket.assigns.symbol

    socket =
      case DataCollector.BinanceClient.get_depth(symbol, 50) do
        {:ok, %{"bids" => bids, "asks" => asks}} ->
          # Convert string prices/quantities to floats for OrderBook component
          parsed_bids = Enum.map(bids, fn [price, qty] ->
            {parse_float(price), parse_float(qty)}
          end)
          parsed_asks = Enum.map(asks, fn [price, qty] ->
            {parse_float(price), parse_float(qty)}
          end)

          # Prepare data for depth chart (as lists for JSON)
          chart_bids = Enum.map(bids, fn [price, qty] ->
            [parse_float(price), parse_float(qty)]
          end)
          chart_asks = Enum.map(asks, fn [price, qty] ->
            [parse_float(price), parse_float(qty)]
          end)

          order_book = %{bids: parsed_bids, asks: parsed_asks}

          socket
          |> assign(order_book: order_book)
          |> push_event("depth_chart_update", %{bids: chart_bids, asks: chart_asks})

        {:error, _reason} ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:start_streams, socket) do
    # Start WebSocket streams if not already running
    symbol = socket.assigns.symbol
    interval = socket.assigns.interval

    # Start depth stream
    try do
      case DataCollector.DepthStream.start_link(symbol: symbol) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        _ -> :ok
      end
    rescue
      _ -> :ok
    end

    # Start kline stream
    try do
      case DataCollector.KlineStream.start_link(symbol: symbol, interval: interval) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        _ -> :ok
      end
    rescue
      _ -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_open_orders, socket) do
    socket = reload_open_orders(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:depth_update, depth_data}, socket) do
    # Throttle order book updates to prevent UI flickering
    now = System.monotonic_time(:millisecond)
    last_update = socket.assigns.last_depth_update
    has_pending = socket.assigns.pending_depth != nil

    if now - last_update >= @depth_throttle_ms do
      # Enough time has passed, update immediately
      order_book = %{
        bids: depth_data.bids,
        asks: depth_data.asks
      }
      {:noreply, socket |> assign(order_book: order_book, last_depth_update: now, pending_depth: nil)}
    else
      # Store pending update
      socket = assign(socket, pending_depth: depth_data)

      # Schedule flush timer only if not already scheduled
      unless has_pending do
        remaining = max(@depth_throttle_ms - (now - last_update), 50)
        Process.send_after(self(), :flush_depth, remaining)
      end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:flush_depth, socket) do
    case socket.assigns.pending_depth do
      nil ->
        {:noreply, socket}

      depth_data ->
        now = System.monotonic_time(:millisecond)
        order_book = %{
          bids: depth_data.bids,
          asks: depth_data.asks
        }
        {:noreply, socket |> assign(order_book: order_book, pending_depth: nil, last_depth_update: now)}
    end
  end

  @impl true
  def handle_info({:kline_update, candle}, socket) do
    # Update price chart with real-time candle
    chart_candle = %{
      time: candle.time,
      open: candle.open,
      high: candle.high,
      low: candle.low,
      close: candle.close,
      volume: candle.volume
    }

    # Also update current price
    socket =
      socket
      |> push_event("price_chart_update", chart_candle)
      |> assign(current_price: Decimal.from_float(candle.close))

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_stream_status, socket) do
    # Load active ticker streams with subscriber counts
    active_streams = DataCollector.TickerStream.list_active_streams()
    {:noreply, assign(socket, active_streams: active_streams)}
  end

  @impl true
  def handle_info({:stream_subscriber_changed, symbol, count}, socket) do
    # Update the specific stream's subscriber count
    active_streams = socket.assigns.active_streams
    |> Enum.reject(fn {s, _} -> s == symbol end)
    |> then(fn streams ->
      if count > 0, do: [{symbol, count} | streams], else: streams
    end)
    |> Enum.sort_by(fn {s, _} -> s end)

    {:noreply, assign(socket, active_streams: active_streams)}
  end

  @impl true
  def handle_info({:stream_stopped, symbol}, socket) do
    # Remove stopped stream from list
    active_streams = Enum.reject(socket.assigns.active_streams, fn {s, _} -> s == symbol end)
    {:noreply, assign(socket, active_streams: active_streams)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  defp parse_float(val) when is_binary(val), do: String.to_float(val)
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val * 1.0

  @impl true
  def handle_event("change_symbol", %{"symbol" => symbol}, socket) do
    # Update symbol and reload data
    socket =
      socket
      |> assign(symbol: symbol)
      |> assign(current_price: nil)
      |> assign(order_book: %{bids: [], asks: []})
      |> assign(order_form: Map.put(socket.assigns.order_form, "symbol", symbol))
      |> assign(symbol_search: "")
      |> assign(show_symbol_dropdown: false)

    # Reload chart data and order book for new symbol
    send(self(), :load_initial_chart_data)
    send(self(), :load_order_book)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_symbol", %{"value" => query}, socket) do
    query = String.upcase(String.trim(query))

    results =
      if String.length(query) >= 1 do
        socket.assigns.available_symbols
        |> Enum.filter(fn sym ->
          String.contains?(sym, query)
        end)
        |> Enum.take(10)
      else
        []
      end

    socket =
      socket
      |> assign(symbol_search: query)
      |> assign(symbol_search_results: results)
      |> assign(show_symbol_dropdown: length(results) > 0)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_symbol", %{"symbol" => symbol}, socket) do
    # Same as change_symbol but from search
    socket =
      socket
      |> assign(symbol: symbol)
      |> assign(current_price: nil)
      |> assign(order_book: %{bids: [], asks: []})
      |> assign(order_form: Map.put(socket.assigns.order_form, "symbol", symbol))
      |> assign(symbol_search: "")
      |> assign(symbol_search_results: [])
      |> assign(show_symbol_dropdown: false)

    send(self(), :load_initial_chart_data)
    send(self(), :load_order_book)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_symbol_dropdown", _, socket) do
    {:noreply, assign(socket, show_symbol_dropdown: false)}
  end

  @impl true
  def handle_event("update_form", %{"order" => params}, socket) do
    {:noreply, assign(socket, order_form: params)}
  end

  @impl true
  def handle_event("create_order", %{"order" => params}, socket) do
    # Валидация параметров
    with {:ok, validated_params} <- validate_order_params(params),
         {api_key, secret_key} <- get_testnet_credentials() || {:error, :no_credentials} do

      # Построить параметры ордера в зависимости от типа
      order_params = build_order_params(validated_params)

      case DataCollector.BinanceClient.create_order(api_key, secret_key, order_params) do
        {:ok, result} ->
          socket =
            socket
            |> put_flash(:info, "Order created successfully! Order ID: #{result["orderId"]}")
            |> assign(order_result: result)
            |> assign(
              order_form: %{
                "symbol" => "BTCUSDT",
                "side" => "BUY",
                "type" => "LIMIT",
                "quantity" => "",
                "price" => ""
              }
            )

          send(self(), :load_balances)
          {:noreply, socket}

        {:error, reason} ->
          error_msg = parse_binance_error(reason)
          {:noreply, put_flash(socket, :error, "Failed to create order: #{error_msg}")}
      end
    else
      {:error, :no_credentials} ->
        {:noreply, put_flash(socket, :error, "Testnet credentials not configured. Check BINANCE_API_KEY and BINANCE_SECRET_KEY env vars.")}

      {:error, validation_error} ->
        {:noreply, put_flash(socket, :error, validation_error)}
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

  # Валидация параметров ордера
  defp validate_order_params(params) do
    symbol = params["symbol"]
    side = params["side"]
    type = params["type"]
    quantity = String.trim(params["quantity"] || "")
    price = String.trim(params["price"] || "")

    cond do
      symbol not in ["BTCUSDT", "ETHUSDT", "BNBUSDT"] ->
        {:error, "Invalid symbol"}

      side not in ["BUY", "SELL"] ->
        {:error, "Invalid side"}

      type not in ["LIMIT", "MARKET"] ->
        {:error, "Invalid order type"}

      quantity == "" ->
        {:error, "Quantity is required"}

      not valid_number?(quantity) ->
        {:error, "Invalid quantity format"}

      type == "LIMIT" && price == "" ->
        {:error, "Price is required for LIMIT orders"}

      type == "LIMIT" && not valid_number?(price) ->
        {:error, "Invalid price format"}

      true ->
        {:ok, %{
          symbol: symbol,
          side: side,
          type: type,
          quantity: quantity,
          price: price
        }}
    end
  end

  defp valid_number?(str) do
    case Float.parse(str) do
      {num, ""} when num > 0 -> true
      _ -> false
    end
  end

  # Построить параметры ордера для Binance API
  defp build_order_params(%{type: "MARKET"} = params) do
    # MARKET ордера не требуют price и timeInForce
    %{
      symbol: params.symbol,
      side: params.side,
      type: "MARKET",
      quantity: params.quantity
    }
  end

  defp build_order_params(%{type: "LIMIT"} = params) do
    %{
      symbol: params.symbol,
      side: params.side,
      type: "LIMIT",
      quantity: params.quantity,
      price: params.price,
      timeInForce: "GTC"
    }
  end

  # Парсинг ошибок Binance API для понятного вывода
  defp parse_binance_error(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "MIN_NOTIONAL") ->
        "Order value too small. Minimum order value is 5 USDT. Increase quantity or price."

      String.contains?(reason, "LOT_SIZE") ->
        "Invalid quantity. Check minimum quantity for this pair (BTCUSDT: 0.00001, ETHUSDT: 0.0001)."

      String.contains?(reason, "PRICE_FILTER") ->
        "Invalid price. Price must be within valid range and tick size."

      String.contains?(reason, "Invalid API-key") ->
        "Invalid API key. Please check your testnet credentials."

      String.contains?(reason, "Signature") ->
        "Signature error. Please check your secret key."

      String.contains?(reason, "Timestamp") ->
        "Timestamp error. Please check your system time."

      true ->
        reason
    end
  end

  defp parse_binance_error(reason), do: inspect(reason)

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
      <!-- Header with Symbol Selector -->
      <div class="flex flex-wrap justify-between items-center gap-4">
        <div class="flex items-center gap-4">
          <h1 class="text-2xl font-bold text-base-content">Trading</h1>

          <!-- Symbol Search -->
          <div class="relative">
            <div class="flex items-center gap-2">
              <div class="dropdown dropdown-bottom">
                <div class="flex items-center">
                  <input
                    type="text"
                    placeholder="Search symbol..."
                    value={@symbol_search}
                    phx-keyup="search_symbol"
                    phx-focus="search_symbol"
                    class="input input-sm input-bordered w-40"
                  />
                </div>
                <%= if @show_symbol_dropdown and length(@symbol_search_results) > 0 do %>
                  <ul class="dropdown-content menu bg-base-200 rounded-box z-50 w-52 p-2 shadow-lg mt-1 max-h-60 overflow-y-auto">
                    <%= for sym <- @symbol_search_results do %>
                      <li>
                        <button
                          phx-click="select_symbol"
                          phx-value-symbol={sym}
                          class="text-left"
                        >
                          <span class="font-mono font-medium"><%= String.replace(sym, "USDT", "") %></span>
                          <span class="text-xs text-base-content/50">/USDT</span>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>

              <!-- Current Symbol Badge -->
              <div class="badge badge-primary badge-lg font-mono">
                <%= @symbol %>
              </div>
            </div>
          </div>

          <!-- Quick Select Buttons -->
          <div class="hidden md:flex gap-1">
            <%= for sym <- ["BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT"] do %>
              <button
                phx-click="change_symbol"
                phx-value-symbol={sym}
                class={[
                  "btn btn-xs",
                  if(@symbol == sym, do: "btn-primary", else: "btn-ghost")
                ]}
              >
                <%= String.replace(sym, "USDT", "") %>
              </button>
            <% end %>
          </div>
        </div>

        <%= if @current_price do %>
          <div class="text-right">
            <div class="text-sm text-base-content/70"><%= @symbol %></div>
            <div class="text-2xl font-bold text-base-content">
              $<%= DecimalHelper.format(@current_price, 2) %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- System Status Panel -->
      <%= if length(@active_streams) > 0 do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="px-6 py-4 border-b border-base-300 flex justify-between items-center">
            <h2 class="text-lg font-semibold text-base-content">Active Streams</h2>
            <span class="badge badge-success badge-sm">
              <%= length(@active_streams) %> active
            </span>
          </div>
          <div class="px-6 py-4">
            <div class="flex flex-wrap gap-2">
              <%= for {symbol, count} <- @active_streams do %>
                <div class="badge badge-outline gap-2">
                  <span class="font-mono text-sm"><%= symbol %></span>
                  <span class="badge badge-primary badge-xs"><%= count %></span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Price Chart -->
      <div class="grid grid-cols-1 gap-4">
        <PriceChart.price_chart id={"price-chart-#{@symbol}"} />
      </div>

      <!-- Market Depth Chart -->
      <div class="grid grid-cols-1 gap-4">
        <DepthChart.depth_chart id={"depth-chart-#{@symbol}"} />
      </div>

      <!-- Market Prices -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <%= for {symbol, price} <- @prices do %>
          <div class="card bg-base-100 shadow-xl p-4">
            <div class="text-sm text-base-content/70"><%= symbol %></div>
            <div class="text-xl font-bold text-base-content">
              <%= if price, do: "$#{price}", else: "Loading..." %>
            </div>
          </div>
        <% end %>
      </div>
      <!-- Testnet Balances -->
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">Testnet Balances</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@balances) do %>
            <div class="px-6 py-8 text-center text-base-content/70">
              Loading balances...
            </div>
          <% else %>
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Asset</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">Free</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Locked
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for balance <- @balances do %>
                  <tr>
                    <td class="whitespace-nowrap text-sm font-medium text-base-content">
                      <%= balance["asset"] %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= balance["free"] %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content/70 text-right">
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
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">Create Test Order</h2>
        </div>
        <div class="px-6 py-4">
          <form phx-change="update_form" phx-submit="create_order">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/70">Symbol</label>
                <select name="order[symbol]" class="mt-1 select select-bordered w-full">
                  <option value="BTCUSDT" selected={@order_form["symbol"] == "BTCUSDT"}>
                    BTC/USDT
                  </option>
                  <option value="ETHUSDT" selected={@order_form["symbol"] == "ETHUSDT"}>
                    ETH/USDT
                  </option>
                  <option value="BNBUSDT" selected={@order_form["symbol"] == "BNBUSDT"}>
                    BNB/USDT
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/70">Side</label>
                <select name="order[side]" class="mt-1 select select-bordered w-full">
                  <option value="BUY" selected={@order_form["side"] == "BUY"}>BUY</option>
                  <option value="SELL" selected={@order_form["side"] == "SELL"}>SELL</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/70">Type</label>
                <select name="order[type]" class="mt-1 select select-bordered w-full">
                  <option value="LIMIT" selected={@order_form["type"] == "LIMIT"}>LIMIT</option>
                  <option value="MARKET" selected={@order_form["type"] == "MARKET"}>MARKET</option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/70">Quantity</label>
                <input
                  type="text"
                  name="order[quantity]"
                  value={@order_form["quantity"]}
                  class="mt-1 input input-bordered w-full"
                  placeholder="0.001"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/70">
                  Price (LIMIT only)
                </label>
                <input
                  type="text"
                  name="order[price]"
                  value={@order_form["price"]}
                  class="mt-1 input input-bordered w-full"
                  placeholder="50000"
                />
              </div>
            </div>
            <div class="mt-4">
              <button type="submit" class="btn btn-primary">
                Create Order
              </button>
            </div>
          </form>

          <%= if @order_result do %>
            <div class="mt-4 alert alert-success">
              <div class="text-sm font-medium">
                Order Created Successfully!
              </div>
              <div class="text-xs mt-2">
                Order ID: <%= @order_result["orderId"] %> |
                Status: <%= @order_result["status"] %> |
                Symbol: <%= @order_result["symbol"] %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Open Orders (from Binance API) -->
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">Open Orders</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@open_orders) do %>
            <div class="px-6 py-8 text-center text-base-content/70">
              No open orders
            </div>
          <% else %>
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Symbol</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Type</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Side</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">Price</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Quantity
                  </th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Filled
                  </th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for order <- @open_orders do %>
                  <tr>
                    <td class="whitespace-nowrap text-sm font-medium text-base-content">
                      <%= order.symbol %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content/70">
                      <%= order.type %>
                    </td>
                    <td class="whitespace-nowrap text-sm">
                      <span class={[
                        "badge",
                        if(order.side == "BUY", do: "badge-success", else: "badge-error")
                      ]}>
                        <%= order.side %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= order.price %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= order.quantity %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= order.filled_quantity %>
                    </td>
                    <td class="whitespace-nowrap text-sm">
                      <span class="badge badge-info">
                        <%= order.status %>
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
      <!-- Active Orders -->
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">Active Orders (Database)</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@active_orders) do %>
            <div class="px-6 py-8 text-center text-base-content/70">
              No active orders
            </div>
          <% else %>
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Symbol</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Type</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Side</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">Price</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Quantity
                  </th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Filled
                  </th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Status</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for order <- @active_orders do %>
                  <tr>
                    <td class="whitespace-nowrap text-sm font-medium text-base-content">
                      <%= order.symbol %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content/70">
                      <%= order.type %>
                    </td>
                    <td class="whitespace-nowrap text-sm">
                      <span class={[
                        "badge",
                        if(order.side == "BUY", do: "badge-success", else: "badge-error")
                      ]}>
                        <%= order.side %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= if order.price, do: DecimalHelper.format(order.price, 2), else: "MARKET" %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= DecimalHelper.format(order.quantity, 6) %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= DecimalHelper.format(order.filled_qty, 6) %>
                    </td>
                    <td class="whitespace-nowrap text-sm">
                      <span class="badge badge-info">
                        <%= order.status %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap text-right text-sm font-medium">
                      <button
                        phx-click="cancel_order"
                        phx-value-id={order.id}
                        class="btn btn-ghost btn-xs text-error"
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
      <div class="card bg-base-100 shadow-xl">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-xl font-semibold text-base-content">Recent Trades</h2>
        </div>
        <div class="overflow-x-auto">
          <%= if Enum.empty?(@recent_trades) do %>
            <div class="px-6 py-8 text-center text-base-content/70">
              No recent trades
            </div>
          <% else %>
            <table class="table table-zebra">
              <thead>
                <tr>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Time</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Symbol</th>
                  <th class="text-left text-xs font-medium text-base-content/70 uppercase">Side</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">Price</th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">
                    Quantity
                  </th>
                  <th class="text-right text-xs font-medium text-base-content/70 uppercase">P&L</th>
                </tr>
              </thead>
              <tbody>
                <%= for trade <- @recent_trades do %>
                  <tr>
                    <td class="whitespace-nowrap text-sm text-base-content/70">
                      <%= Calendar.strftime(trade.timestamp, "%H:%M:%S") %>
                    </td>
                    <td class="whitespace-nowrap text-sm font-medium text-base-content">
                      <%= trade.symbol %>
                    </td>
                    <td class="whitespace-nowrap text-sm">
                      <span class={[
                        "badge",
                        if(trade.side == "BUY", do: "badge-success", else: "badge-error")
                      ]}>
                        <%= trade.side %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= DecimalHelper.format(trade.price, 2) %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-base-content text-right">
                      <%= DecimalHelper.format(trade.quantity, 6) %>
                    </td>
                    <td class="whitespace-nowrap text-sm text-right">
                      <%= if trade.pnl do %>
                        <span class={[
                          "font-medium",
                          if(DecimalHelper.positive?(trade.pnl),
                            do: "text-success",
                            else: "text-error"
                          )
                        ]}>
                          <%= DecimalHelper.format_currency(trade.pnl, "USDT", 2) %>
                        </span>
                      <% else %>
                        <span class="text-base-content/50">-</span>
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
    # Try to get credentials from database (for authenticated user) or fallback to env vars
    # Phase 8: Will pass actual user_id from authenticated session
    user_id = nil
    CredentialHelper.get_credentials(user_id)
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

  defp reload_open_orders(socket) do
    open_orders =
      case get_testnet_credentials() do
        {api_key, secret_key} ->
          symbol = socket.assigns.symbol

          case DataCollector.BinanceClient.get_open_orders(api_key, secret_key, symbol) do
            {:ok, orders} ->
              # Convert to format suitable for display
              Enum.map(orders, fn order ->
                %{
                  order_id: order["orderId"],
                  symbol: order["symbol"],
                  side: order["side"],
                  type: order["type"],
                  price: order["price"],
                  quantity: order["origQty"],
                  filled_quantity: order["executedQty"],
                  status: order["status"],
                  time: order["time"]
                }
              end)

            {:error, _reason} ->
              []
          end

        nil ->
          []
      end

    assign(socket, open_orders: open_orders)
  end
end
