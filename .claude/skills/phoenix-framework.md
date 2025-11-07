---
name: phoenix-framework
description: Guide for building Phoenix applications including umbrella projects, configuration, routing, and Phoenix.PubSub. Use when setting up new Phoenix projects, configuring umbrella apps, or implementing real-time features.
---

# Phoenix Framework Development

## Umbrella Project Structure

```bash
mix new binance_system --umbrella
cd binance_system/apps
mix phx.new dashboard_web --no-ecto
mix new trading_engine --sup
mix new data_collector --sup
```

## Application Configuration

```elixir
# config/config.exs
import Config

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

# config/runtime.exs
import Config

if config_env() == :prod do
  config :my_app, MyAppWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"],
    http: [port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
```

## Phoenix.PubSub

```elixir
# In application.ex
children = [
  {Phoenix.PubSub, name: MyApp.PubSub}
]

# Broadcasting
Phoenix.PubSub.broadcast(MyApp.PubSub, "market:BTCUSDT", {:price_update, price})

# Subscribing
Phoenix.PubSub.subscribe(MyApp.PubSub, "market:BTCUSDT")

# In GenServer
def handle_info({:price_update, price}, state) do
  # Handle event
  {:noreply, state}
end
```
