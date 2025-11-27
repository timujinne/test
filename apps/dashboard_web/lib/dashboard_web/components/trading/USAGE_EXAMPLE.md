# Trading Components Usage Examples

This document demonstrates how to integrate the OrderBook and OrderForm components into LiveView pages.

## 1. Import the Components

Add to your LiveView module:

```elixir
defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view

  # Import trading components
  import DashboardWeb.Components.Trading

  # ... rest of your module
end
```

## 2. OrderBook Component

### Basic Usage

```elixir
<.order_book
  symbol="BTCUSDT"
  bids={@bids}
  asks={@asks}
/>
```

### Full Example with LiveView

```elixir
defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view
  import DashboardWeb.Components.Trading

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
    end

    socket =
      socket
      |> assign(:symbol, "BTCUSDT")
      |> assign(:bids, [])
      |> assign(:asks, [])
      |> assign(:precision, 2)

    {:ok, socket}
  end

  def handle_info({:depth_update, %{"bids" => bids, "asks" => asks}}, socket) do
    # Convert from Binance format: [["price", "qty"], ...]
    # to component format: [{price, qty}, ...]
    parsed_bids =
      bids
      |> Enum.map(fn [price, qty] ->
        {String.to_float(price), String.to_float(qty)}
      end)

    parsed_asks =
      asks
      |> Enum.map(fn [price, qty] ->
        {String.to_float(price), String.to_float(qty)}
      end)

    socket =
      socket
      |> assign(:bids, parsed_bids)
      |> assign(:asks, parsed_asks)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <!-- OrderBook takes 1 column -->
      <div>
        <.order_book
          symbol={@symbol}
          bids={@bids}
          asks={@asks}
          precision={@precision}
          rows={16}
        />
      </div>

      <!-- Other content -->
      <div class="lg:col-span-2">
        <!-- Charts, etc. -->
      </div>
    </div>
    """
  end
end
```

### OrderBook Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `bids` | `list` | No | `[]` | List of bid orders as `[{price, quantity}, ...]` |
| `asks` | `list` | No | `[]` | List of ask orders as `[{price, quantity}, ...]` |
| `symbol` | `string` | Yes | - | Trading pair symbol (e.g., "BTCUSDT") |
| `precision` | `integer` | No | `2` | Decimal places for price formatting |
| `rows` | `integer` | No | `12` | Total number of price levels to display (split between asks/bids) |

## 3. OrderForm Component

### Basic Usage

```elixir
<.order_form
  form={@order_form}
  symbol={@symbol}
  current_price={@current_price}
  available_balance={@balance}
  base_asset="BTC"
  quote_asset="USDT"
/>
```

### Full Example with Event Handlers

```elixir
defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view
  import DashboardWeb.Components.Trading

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:symbol, "BTCUSDT")
      |> assign(:current_price, 42000.50)
      |> assign(:balance, "1000.00")
      |> assign(:order_form, %{
        "side" => "BUY",
        "type" => "LIMIT",
        "price" => "",
        "quantity" => ""
      })

    {:ok, socket}
  end

  # Handle side change (BUY/SELL)
  def handle_event("change_side", %{"side" => side}, socket) do
    order_form = Map.put(socket.assigns.order_form, "side", side)
    {:noreply, assign(socket, :order_form, order_form)}
  end

  # Handle order type change (LIMIT/MARKET)
  def handle_event("change_order_type", %{"value" => type}, socket) do
    order_form = Map.put(socket.assigns.order_form, "type", type)
    {:noreply, assign(socket, :order_form, order_form)}
  end

  # Handle price input change
  def handle_event("update_price", %{"value" => price}, socket) do
    order_form = Map.put(socket.assigns.order_form, "price", price)
    {:noreply, assign(socket, :order_form, order_form)}
  end

  # Handle quantity input change
  def handle_event("update_quantity", %{"value" => quantity}, socket) do
    order_form = Map.put(socket.assigns.order_form, "quantity", quantity)
    {:noreply, assign(socket, :order_form, order_form)}
  end

  # Handle percentage button clicks
  def handle_event("set_percentage", %{"percent" => percent_str}, socket) do
    %{order_form: form, balance: balance, current_price: price} = socket.assigns

    percent = String.to_integer(percent_str)
    side = Map.get(form, "side", "BUY")
    order_type = Map.get(form, "type", "LIMIT")

    # Calculate quantity based on percentage
    quantity = calculate_quantity_from_percent(percent, balance, price, side, order_type, form)

    order_form = Map.put(form, "quantity", Float.to_string(quantity))
    {:noreply, assign(socket, :order_form, order_form)}
  end

  # Handle order submission
  def handle_event("place_order", _params, socket) do
    %{order_form: form, symbol: symbol} = socket.assigns

    order_params = %{
      symbol: symbol,
      side: form["side"],
      type: form["type"],
      quantity: form["quantity"],
      price: form["price"],
      timeInForce: "GTC"
    }

    case create_order(order_params) do
      {:ok, result} ->
        socket =
          socket
          |> put_flash(:info, "Order placed successfully!")
          |> reset_order_form()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to place order: #{reason}")}
    end
  end

  defp calculate_quantity_from_percent(percent, balance, price, side, type, form) do
    {balance_float, _} = Float.parse(balance)
    amount_to_use = balance_float * (percent / 100.0)

    case {side, type} do
      {"BUY", "LIMIT"} ->
        # For BUY LIMIT: divide available USDT by limit price
        case Float.parse(Map.get(form, "price", "0")) do
          {limit_price, _} when limit_price > 0 -> amount_to_use / limit_price
          _ -> 0.0
        end

      {"BUY", "MARKET"} ->
        # For BUY MARKET: divide available USDT by current price
        amount_to_use / price

      {"SELL", _} ->
        # For SELL: use percentage of BTC balance
        amount_to_use
    end
  end

  defp reset_order_form(socket) do
    assign(socket, :order_form, %{
      "side" => "BUY",
      "type" => "LIMIT",
      "price" => "",
      "quantity" => ""
    })
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <!-- OrderForm takes 1 column -->
      <div>
        <.order_form
          form={@order_form}
          symbol={@symbol}
          current_price={@current_price}
          available_balance={@balance}
          base_asset="BTC"
          quote_asset="USDT"
        />
      </div>

      <!-- Other content -->
      <div class="lg:col-span-2">
        <!-- Charts, tables, etc. -->
      </div>
    </div>
    """
  end
end
```

### OrderForm Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `form` | `map` | Yes | - | Form state map with keys: "side", "type", "price", "quantity" |
| `symbol` | `string` | Yes | - | Trading pair symbol (e.g., "BTCUSDT") |
| `current_price` | `number` | No | `nil` | Current market price for the symbol |
| `available_balance` | `string` | No | `"0.00"` | Available balance for trading |
| `base_asset` | `string` | No | `"BTC"` | Base asset symbol |
| `quote_asset` | `string` | No | `"USDT"` | Quote asset symbol |

### Required Event Handlers

The OrderForm component emits these Phoenix events that must be handled:

- `"change_side"` - When BUY/SELL tab is clicked (params: `%{"side" => "BUY"|"SELL"}`)
- `"change_order_type"` - When order type select changes (params: `%{"value" => "LIMIT"|"MARKET"}`)
- `"update_price"` - When price input changes (params: `%{"value" => price_string}`)
- `"update_quantity"` - When quantity input changes (params: `%{"value" => quantity_string}`)
- `"set_percentage"` - When percentage buttons are clicked (params: `%{"percent" => "25"|"50"|"75"|"100"}`)
- `"place_order"` - When submit button is clicked (params: empty)

## 4. Combined Example - Full Trading Interface

```elixir
defmodule DashboardWeb.TradingLive do
  use DashboardWeb, :live_view
  import DashboardWeb.Components.Trading

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:BTCUSDT")
    end

    socket =
      socket
      |> assign(:symbol, "BTCUSDT")
      |> assign(:bids, example_bids())
      |> assign(:asks, example_asks())
      |> assign(:current_price, 42000.50)
      |> assign(:btc_balance, "0.5")
      |> assign(:usdt_balance, "10000.00")
      |> assign(:order_form, %{
        "side" => "BUY",
        "type" => "LIMIT",
        "price" => "",
        "quantity" => ""
      })

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-3xl font-bold">Trading - {@symbol}</h1>

      <!-- Main trading layout -->
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-4">
        <!-- OrderBook - Left sidebar -->
        <div class="lg:col-span-3">
          <.order_book
            symbol={@symbol}
            bids={@bids}
            asks={@asks}
            precision={2}
            rows={20}
          />
        </div>

        <!-- Chart area - Center (placeholder) -->
        <div class="lg:col-span-6">
          <div class="card bg-base-100 shadow-xl h-[600px]">
            <div class="card-body">
              <h2 class="card-title">Price Chart</h2>
              <div class="flex-1 flex items-center justify-center text-base-content/60">
                Chart component here
              </div>
            </div>
          </div>
        </div>

        <!-- OrderForm - Right sidebar -->
        <div class="lg:col-span-3">
          <.order_form
            form={@order_form}
            symbol={@symbol}
            current_price={@current_price}
            available_balance={get_available_balance(@order_form, @btc_balance, @usdt_balance)}
            base_asset="BTC"
            quote_asset="USDT"
          />
        </div>
      </div>
    </div>
    """
  end

  defp get_available_balance(%{"side" => "BUY"}, _btc, usdt), do: usdt
  defp get_available_balance(%{"side" => "SELL"}, btc, _usdt), do: btc
  defp get_available_balance(_, _btc, usdt), do: usdt

  defp example_bids do
    [
      {41995.50, 1.234},
      {41995.00, 0.567},
      {41994.50, 2.345},
      {41994.00, 0.891},
      {41993.50, 1.567}
    ]
  end

  defp example_asks do
    [
      {42000.50, 0.987},
      {42001.00, 1.456},
      {42001.50, 0.654},
      {42002.00, 2.123},
      {42002.50, 0.789}
    ]
  end
end
```

## 5. Styling Notes

Both components use DaisyUI classes and support dark/light themes automatically:

- Colors adapt to the current DaisyUI theme
- Use semantic color classes: `text-success` (green), `text-error` (red)
- All spacing and sizing use Tailwind utilities
- Components are responsive and mobile-friendly

## 6. Data Format

### OrderBook Expected Format

```elixir
# Bids and asks are lists of tuples: {price, quantity}
bids = [
  {42000.00, 1.5},   # price: 42000.00, quantity: 1.5 BTC
  {41999.50, 0.8},
  {41999.00, 2.3}
]

asks = [
  {42001.00, 0.5},
  {42001.50, 1.2},
  {42002.00, 0.9}
]
```

### OrderForm Expected Format

```elixir
form = %{
  "side" => "BUY",          # "BUY" or "SELL"
  "type" => "LIMIT",        # "LIMIT" or "MARKET"
  "price" => "42000.00",    # String, empty for MARKET orders
  "quantity" => "0.5"       # String
}
```

## 7. Testing Components

You can test the components in IEx:

```elixir
# Start the app
iex -S mix phx.server

# Test data
assigns = %{
  symbol: "BTCUSDT",
  bids: [{42000.0, 1.5}, {41999.5, 2.0}],
  asks: [{42001.0, 0.8}, {42001.5, 1.2}],
  precision: 2,
  rows: 12
}

# Components are just functions that return rendered HTML
DashboardWeb.Components.Trading.OrderBook.order_book(assigns)
```
