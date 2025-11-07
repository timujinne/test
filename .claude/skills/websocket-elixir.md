---
name: websocket-elixir
description: WebSocket client implementation in Elixir using WebSockex including reconnection strategies, error handling, and supervision. Use when connecting to external WebSocket APIs like Binance, implementing streaming data clients, or building WebSocket integrations.
---

# WebSocket Client with WebSockex

## Basic WebSocket Client

```elixir
defmodule MyApp.WebSocketClient do
  use WebSockex

  def start_link(url, state \\ %{}) do
    WebSockex.start_link(url, __MODULE__, state, name: __MODULE__)
  end

  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} -> process_message(data, state)
      {:error, _} -> {:ok, state}
    end
  end

  def handle_frame({:binary, msg}, state) do
    # Handle binary messages
    {:ok, state}
  end

  def handle_ping({:ping, msg}, state) do
    {:reply, {:pong, msg}, state}
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.warn("Disconnected: #{inspect(reason)}")
    {:reconnect, state}
  end

  def handle_reconnect(_conn_status, state) do
    Logger.info("Reconnecting...")
    {:ok, state}
  end
end
```

## Exponential Backoff

```elixir
defmodule MyApp.WebSocketWithBackoff do
  use WebSockex

  def handle_disconnect(%{reason: reason}, state) do
    backoff = calculate_backoff(state.retry_count)
    Logger.warn("Disconnected, retrying in #{backoff}ms")
    Process.sleep(backoff)
    {:reconnect, %{state | retry_count: state.retry_count + 1}}
  end

  defp calculate_backoff(retry_count) do
    min(5_000 * :math.pow(2, retry_count), 60_000) |> trunc()
  end
end
```
