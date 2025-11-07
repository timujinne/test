---
name: phoenix-channels
description: Implementation guide for Phoenix Channels including WebSocket communication, channel architecture, presence tracking, and real-time updates. Use when building real-time features, chat systems, or live dashboards.
---

# Phoenix Channels

## Channel Setup

```elixir
# lib/my_app_web/channels/user_socket.ex
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "market:*", MyAppWeb.MarketChannel
  channel "orders:*", MyAppWeb.OrdersChannel

  def connect(%{"token" => token}, socket, _connect_info) do
    case verify_token(token) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      _ -> :error
    end
  end

  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
```

## Channel Implementation

```elixir
defmodule MyAppWeb.MarketChannel do
  use Phoenix.Channel

  def join("market:" <> symbol, _params, socket) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "market:#{symbol}")
    send(self(), {:after_join, symbol})
    {:ok, assign(socket, :symbol, symbol)}
  end

  def handle_info({:after_join, symbol}, socket) do
    price = get_current_price(symbol)
    push(socket, "market_snapshot", %{symbol: symbol, price: price})
    {:noreply, socket}
  end

  def handle_info({:price_update, price}, socket) do
    push(socket, "tick", %{p: price, t: System.system_time(:millisecond)})
    {:noreply, socket}
  end

  def handle_in("subscribe_depth", %{"levels" => levels}, socket) do
    # Client-initiated subscription
    {:reply, {:ok, %{subscribed: true}}, socket}
  end
end
```

## Client-Side JavaScript

```javascript
import {Socket} from "phoenix"

let socket = new Socket("/socket", {params: {token: userToken}})
socket.connect()

let channel = socket.channel("market:BTCUSDT", {})

channel.on("tick", payload => {
  updatePrice(payload.p)
})

channel.join()
  .receive("ok", resp => console.log("Joined", resp))
  .receive("error", resp => console.log("Error", resp))
```
