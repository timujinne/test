---
name: phoenix-liveview
description: Guide for building real-time interactive web interfaces with Phoenix LiveView. This skill should be used when creating reactive dashboards, real-time data displays, form handling, or any server-rendered interactive UI without JavaScript complexity.
---

# Phoenix LiveView Development

This skill provides guidance for building real-time, interactive web applications using Phoenix LiveView.

## When to Use This Skill

- Building real-time dashboards with live data updates
- Creating interactive forms with instant validation
- Implementing reactive UI without writing JavaScript
- Developing trading dashboards or monitoring systems
- Building collaborative tools with real-time updates

## Core LiveView Concepts

### Mount and Lifecycle

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to updates only after WebSocket connected
      Phoenix.PubSub.subscribe(MyApp.PubSub, "market:updates")
      # Schedule periodic updates
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok, assign(socket, prices: %{}, last_update: DateTime.utc_now())}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, last_update: DateTime.utc_now())}
  end

  def handle_info({:price_update, symbol, price}, socket) do
    prices = Map.put(socket.assigns.prices, symbol, price)
    {:noreply, assign(socket, prices: prices)}
  end
end
```

### Streams for Efficient List Updates

Use streams for large, frequently updating lists:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :trades, fetch_recent_trades(), limit: 50)}
end

def handle_info({:new_trade, trade}, socket) do
  # Only new trade sent to client, not entire list
  {:noreply, stream_insert(socket, :trades, trade, at: 0)}
end

def render(assigns) do
  ~H"""
  <div id="trades" phx-update="stream">
    <div :for={{id, trade} <- @streams.trades} id={id}>
      <%= trade.symbol %> - <%= trade.price %>
    </div>
  </div>
  """
end
```

### Forms and Validation

```elixir
def render(assigns) do
  ~H"""
  <.form for={@form} phx-change="validate" phx-submit="save">
    <.input field={@form[:amount]} label="Amount" />
    <.input field={@form[:price]} label="Price" />
    <.button>Place Order</.button>
  </.form>
  """
end

def handle_event("validate", %{"order" => params}, socket) do
  changeset = Order.changeset(%Order{}, params)
  {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
end

def handle_event("save", %{"order" => params}, socket) do
  case Orders.create_order(params) do
    {:ok, order} -> {:noreply, push_navigate(socket, to: ~p"/orders/#{order}")}
    {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

### JavaScript Interop with Hooks

```javascript
// app.js
let Hooks = {}

Hooks.PriceFlash = {
  mounted() {
    this.el.addEventListener("phx:price-updated", e => {
      this.el.classList.add("flash-green")
      setTimeout(() => this.el.classList.remove("flash-green"), 500)
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks})
```

```elixir
def handle_info({:price_update, price}, socket) do
  {:noreply, 
   socket
   |> assign(price: price)
   |> push_event("price-updated", %{price: price})}
end
```

## Performance Optimizations

1. **Minimize assigns**: Only send changed data
2. **Use streams**: For large lists with frequent updates
3. **Temporary assigns**: For data not needed after render
4. **Component extraction**: Reduce unnecessary updates

```elixir
def mount(_params, _session, socket) do
  socket = 
    socket
    |> assign(prices: %{})
    |> assign_new(:static_data, fn -> load_static_data() end)
    |> assign(:last_update, DateTime.utc_now())
  
  {:ok, socket, temporary_assigns: [trades: []]}
end
```

## UI Component Libraries

**Recommended:**
- **Petal Components** - Full component library for Phoenix
- **Mishka Chelekom** - UI component system
- **DaisyUI with Tailwind** - Pre-built Tailwind components

**Note**: phoenix_kit is a SaaS starter, NOT a UI component library.

## Best Practices

1. Subscribe to PubSub in `mount` after `connected?(socket)` check
2. Use streams for lists with > 100 items or frequent updates
3. Keep LiveView state minimal - derive what you can
4. Use components to break down complex UIs
5. Implement loading states for better UX
6. Use push_event sparingly for JS interop
7. Test with multiple concurrent users

## Common Patterns

### Modal Dialogs

```elixir
def render(assigns) do
  ~H"""
  <.modal :if={@show_modal} id="order-modal" on_cancel={JS.push("close_modal")}>
    <.form phx-submit="create_order">
      <!-- form content -->
    </.form>
  </.modal>
  """
end
```

### Debounced Search

```elixir
def handle_event("search", %{"query" => query}, socket) do
  Process.send_after(self(), {:search, query}, 300)
  {:noreply, socket}
end

def handle_info({:search, query}, socket) do
  results = search(query)
  {:noreply, assign(socket, results: results)}
end
```

### Upload Handling

```elixir
def mount(_params, _session, socket) do
  {:ok, allow_upload(socket, :avatar, accept: ~w(.jpg .jpeg .png), max_entries: 1)}
end

def handle_event("save", _params, socket) do
  uploaded_files = consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
    dest = Path.join("priv/static/uploads", Path.basename(path))
    File.cp!(path, dest)
    {:ok, "/uploads/" <> Path.basename(dest)}
  end)
  
  {:noreply, assign(socket, uploaded_files: uploaded_files)}
end
```
