defmodule DataCollector.DepthStream do
  @moduledoc """
  WebSocket client for Binance order book (depth) stream.

  Subscribes to partial book depth streams and broadcasts updates via PubSub.

  ## Binance Stream Format

  Stream name: `<symbol>@depth@100ms` for 100ms updates

  Message format:
  ```json
  {
    "e": "depthUpdate",
    "E": 123456789,
    "s": "BTCUSDT",
    "U": 157,
    "u": 160,
    "b": [["9469.00", "100.00"]],
    "a": [["9470.00", "50.00"]]
  }
  ```

  ## PubSub Topics

  Broadcasts to: `depth:<SYMBOL>` (e.g., `depth:BTCUSDT`)
  Message format: `{:depth_update, %{bids: [...], asks: [...], update_id: integer}}`
  """
  use WebSockex
  require Logger

  alias SharedData.Config

  @base_url "wss://stream.binance.com:9443"

  def start_link(opts) do
    symbol = Keyword.fetch!(opts, :symbol) |> String.downcase()
    # btcusdt@depth@100ms - faster updates
    stream = "#{symbol}@depth@100ms"
    url = "#{@base_url}/ws/#{stream}"

    initial_state = %{
      symbol: String.upcase(symbol),
      stream: stream,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    name = via_tuple(String.upcase(symbol))
    WebSockex.start_link(url, __MODULE__, initial_state, name: name)
  end

  def via_tuple(symbol) do
    {:via, Registry, {DataCollector.StreamRegistry, {:depth, symbol}}}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, state)
        # Reset decode errors counter on successful decode
        {:ok, %{state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        DepthStream: Failed to decode WebSocket message
        Symbol: #{state.symbol}
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        # Increment decode errors counter
        new_state = %{state | decode_errors: state.decode_errors + 1}

        # If too many decode errors, reconnect
        if new_state.decode_errors > 10 do
          Logger.error(
            "DepthStream (#{state.symbol}): Too many decode errors (#{new_state.decode_errors}), reconnecting..."
          )

          {:close, :too_many_errors, new_state}
        else
          {:ok, new_state}
        end
    end
  end

  @impl true
  def handle_frame({:ping, _}, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    attempts = state.reconnect_attempts + 1
    max_attempts = Config.websocket(:max_reconnect_attempts)

    if attempts >= max_attempts do
      Logger.error("""
      DepthStream (#{state.symbol}): Max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      # Calculate backoff time with jitter
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      DepthStream (#{state.symbol}): Disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      # Sleep for backoff time
      Process.sleep(backoff_ms)

      # Update state and reconnect
      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("""
    DepthStream (#{state.symbol}): Connected successfully
    Stream: #{state.stream}
    Resetting reconnect attempts counter
    """)

    # Reset counters on successful connection
    new_state = %{state | reconnect_attempts: 0, decode_errors: 0}
    {:ok, new_state}
  end

  # Private functions

  defp handle_message(%{"e" => "depthUpdate"} = data, _state) do
    symbol = data["s"]

    # Transform bids and asks to proper format
    bids = parse_price_levels(data["b"] || [])
    asks = parse_price_levels(data["a"] || [])

    depth_update = %{
      bids: bids,
      asks: asks,
      update_id: data["u"],
      first_update_id: data["U"],
      event_time: data["E"]
    }

    Logger.debug(
      "DepthStream (#{symbol}): Broadcasting depth update (#{length(bids)} bids, #{length(asks)} asks)"
    )

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "depth:#{symbol}",
      {:depth_update, depth_update}
    )
  end

  defp handle_message(data, state) do
    Logger.debug("DepthStream (#{state.symbol}): Unhandled message: #{inspect(data)}")
  end

  # Parse price levels from Binance format [["price", "quantity"], ...]
  # to [{price, quantity}, ...]
  defp parse_price_levels(levels) when is_list(levels) do
    levels
    |> Enum.map(fn [price, qty] ->
      {String.to_float(price), String.to_float(qty)}
    end)
  end

  # Calculate exponential backoff with jitter
  defp calculate_backoff(attempts) do
    base_backoff = Config.websocket(:initial_backoff)
    max_backoff = Config.websocket(:max_backoff)
    multiplier = Config.websocket(:backoff_multiplier)

    # Exponential backoff: base * multiplier^(attempts-1)
    backoff = base_backoff * :math.pow(multiplier, attempts - 1)
    capped_backoff = min(trunc(backoff), max_backoff)

    # Add random jitter (±20%) to prevent thundering herd
    jitter_range = trunc(capped_backoff * 0.2)
    jitter = :rand.uniform(jitter_range * 2 + 1) - jitter_range - 1

    max(capped_backoff + jitter, base_backoff)
  end
end
