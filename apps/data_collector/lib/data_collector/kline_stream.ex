defmodule DataCollector.KlineStream do
  @moduledoc """
  WebSocket client for Binance kline/candlestick stream.

  Subscribes to kline streams for specified intervals and broadcasts updates via PubSub.

  ## Binance Stream Format

  Stream name: `<symbol>@kline_<interval>` (e.g., `btcusdt@kline_1h`)

  Supported intervals: 1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 8h, 12h, 1d, 3d, 1w, 1M

  Message format:
  ```json
  {
    "e": "kline",
    "E": 123456789,
    "s": "BTCUSDT",
    "k": {
      "t": 123400000,
      "T": 123460000,
      "s": "BTCUSDT",
      "i": "1m",
      "f": 100,
      "L": 200,
      "o": "0.0010",
      "c": "0.0020",
      "h": "0.0025",
      "l": "0.0005",
      "v": "1000",
      "n": 100,
      "x": false,
      "q": "1.0000",
      "V": "500",
      "Q": "0.500",
      "B": "123456"
    }
  }
  ```

  ## PubSub Topics

  Broadcasts to: `kline:<SYMBOL>:<INTERVAL>` (e.g., `kline:BTCUSDT:1h`)
  Message format: `{:kline_update, %{time: integer, open: float, high: float, low: float, close: float, volume: float, closed: boolean}}`
  """
  use WebSockex
  require Logger

  alias SharedData.Config

  @base_url "wss://stream.binance.com:9443"
  @valid_intervals ~w(1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d 3d 1w 1M)

  def start_link(opts) do
    symbol = Keyword.fetch!(opts, :symbol) |> String.downcase()
    interval = Keyword.get(opts, :interval, "1h")

    unless interval in @valid_intervals do
      raise ArgumentError,
            "Invalid interval: #{interval}. Valid intervals: #{inspect(@valid_intervals)}"
    end

    # btcusdt@kline_1h
    stream = "#{symbol}@kline_#{interval}"
    url = "#{@base_url}/ws/#{stream}"

    initial_state = %{
      symbol: String.upcase(symbol),
      interval: interval,
      stream: stream,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    name = via_tuple(String.upcase(symbol), interval)
    WebSockex.start_link(url, __MODULE__, initial_state, name: name)
  end

  def via_tuple(symbol, interval) do
    {:via, Registry, {DataCollector.StreamRegistry, {:kline, symbol, interval}}}
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
        KlineStream: Failed to decode WebSocket message
        Symbol: #{state.symbol}, Interval: #{state.interval}
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        # Increment decode errors counter
        new_state = %{state | decode_errors: state.decode_errors + 1}

        # If too many decode errors, reconnect
        if new_state.decode_errors > 10 do
          Logger.error(
            "KlineStream (#{state.symbol}/#{state.interval}): Too many decode errors (#{new_state.decode_errors}), reconnecting..."
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
      KlineStream (#{state.symbol}/#{state.interval}): Max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      # Calculate backoff time with jitter
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      KlineStream (#{state.symbol}/#{state.interval}): Disconnected: #{inspect(reason)}
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
    KlineStream (#{state.symbol}/#{state.interval}): Connected successfully
    Stream: #{state.stream}
    Resetting reconnect attempts counter
    """)

    # Reset counters on successful connection
    new_state = %{state | reconnect_attempts: 0, decode_errors: 0}
    {:ok, new_state}
  end

  # Private functions

  defp handle_message(%{"e" => "kline", "k" => kline_data} = data, state) do
    symbol = data["s"]

    # Transform kline data to standard format
    candle = %{
      time: kline_data["t"],
      close_time: kline_data["T"],
      open: String.to_float(kline_data["o"]),
      high: String.to_float(kline_data["h"]),
      low: String.to_float(kline_data["l"]),
      close: String.to_float(kline_data["c"]),
      volume: String.to_float(kline_data["v"]),
      quote_volume: String.to_float(kline_data["q"]),
      trades: kline_data["n"],
      closed: kline_data["x"],
      interval: kline_data["i"]
    }

    Logger.debug(
      "KlineStream (#{symbol}/#{state.interval}): Broadcasting kline update (closed: #{candle.closed})"
    )

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "kline:#{symbol}:#{state.interval}",
      {:kline_update, candle}
    )
  end

  defp handle_message(data, state) do
    Logger.debug(
      "KlineStream (#{state.symbol}/#{state.interval}): Unhandled message: #{inspect(data)}"
    )
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
