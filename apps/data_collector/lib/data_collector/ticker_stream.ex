defmodule DataCollector.TickerStream do
  @moduledoc """
  WebSocket client for Binance mini ticker stream.

  Subscribes to mini ticker streams for real-time price updates.
  Uses reference counting to automatically stop streams when no subscribers remain.

  ## Binance Stream Format

  Stream name: `<symbol>@miniTicker` (e.g., `btcusdt@miniTicker`)

  Message format:
  ```json
  {
    "e": "24hrMiniTicker",
    "E": 1672515782136,
    "s": "BTCUSDT",
    "c": "16500.00",     // Close price
    "o": "16400.00",     // Open price
    "h": "16600.00",     // High price
    "l": "16300.00",     // Low price
    "v": "1000.00",      // Total traded base asset volume
    "q": "16500000.00"   // Total traded quote asset volume
  }
  ```

  ## PubSub Topics

  Broadcasts to: `market:<SYMBOL>` (e.g., `market:BTCUSDT`)
  Message format: `{:ticker, %{...}}`

  ## Lifecycle Management

  Use `subscribe/1` and `unsubscribe/1` for proper lifecycle management:
  - Stream starts automatically on first subscription
  - Stream stops automatically when last subscriber unsubscribes
  - Multiple subscribers share the same stream
  """
  use WebSockex
  require Logger

  alias SharedData.Config

  @base_url "wss://stream.binance.com:9443"
  @subscribers_table :ticker_subscribers

  def start_link(opts) do
    symbol = Keyword.fetch!(opts, :symbol) |> String.downcase()

    # btcusdt@miniTicker
    stream = "#{symbol}@miniTicker"
    url = "#{@base_url}/ws/#{stream}"

    initial_state = %{
      symbol: String.upcase(symbol),
      stream: stream,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    name = via_tuple(String.upcase(symbol))

    case WebSockex.start_link(url, __MODULE__, initial_state, name: name) do
      {:ok, pid} ->
        Logger.info("TickerStream started for #{String.upcase(symbol)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("TickerStream already running for #{String.upcase(symbol)}")
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Ensure ticker stream is running for a symbol.
  Returns {:ok, pid} if started or already running.

  Note: Prefer using `subscribe/1` for proper lifecycle management.
  """
  def ensure_started(symbol) do
    symbol = String.upcase(symbol)

    case Registry.lookup(DataCollector.StreamRegistry, {:ticker, symbol}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        start_link(symbol: symbol)
    end
  end

  @doc """
  Subscribe to ticker stream for a symbol.
  Starts the stream if not already running.
  Returns {:ok, subscriber_count} on success.

  The stream will automatically stop when all subscribers unsubscribe.
  """
  @spec subscribe(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def subscribe(symbol) do
    symbol = String.upcase(symbol)

    case ensure_started(symbol) do
      {:ok, _pid} ->
        count = :ets.update_counter(@subscribers_table, symbol, 1, {symbol, 0})
        Logger.info("TickerStream (#{symbol}): Subscriber added, count: #{count}")

        # Broadcast subscriber change for dashboard
        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "system:streams",
          {:stream_subscriber_changed, symbol, count}
        )

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Unsubscribe from ticker stream for a symbol.
  Stops the stream if this was the last subscriber.
  Returns {:ok, remaining_count}.
  """
  @spec unsubscribe(String.t()) :: {:ok, non_neg_integer()}
  def unsubscribe(symbol) do
    symbol = String.upcase(symbol)

    # Ensure we don't go below 0
    count =
      case :ets.lookup(@subscribers_table, symbol) do
        [{^symbol, current}] when current > 0 ->
          :ets.update_counter(@subscribers_table, symbol, -1)

        _ ->
          0
      end

    Logger.info("TickerStream (#{symbol}): Subscriber removed, count: #{count}")

    # Broadcast subscriber change for dashboard
    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "system:streams",
      {:stream_subscriber_changed, symbol, count}
    )

    if count <= 0 do
      Logger.info("TickerStream (#{symbol}): No subscribers left, stopping stream")
      stop(symbol)
      :ets.delete(@subscribers_table, symbol)
    end

    {:ok, count}
  end

  @doc """
  Stop the ticker stream for a symbol.
  Called automatically when last subscriber unsubscribes.
  """
  @spec stop(String.t()) :: :ok
  def stop(symbol) do
    symbol = String.upcase(symbol)

    case Registry.lookup(DataCollector.StreamRegistry, {:ticker, symbol}) do
      [{pid, _}] ->
        Logger.info("TickerStream (#{symbol}): Stopping stream")
        GenServer.stop(pid, :normal)

        # Broadcast stream stopped for dashboard
        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "system:streams",
          {:stream_stopped, symbol}
        )

        :ok

      [] ->
        :ok
    end
  end

  @doc """
  Get current subscriber count for a symbol.
  """
  @spec subscriber_count(String.t()) :: non_neg_integer()
  def subscriber_count(symbol) do
    symbol = String.upcase(symbol)

    case :ets.lookup(@subscribers_table, symbol) do
      [{^symbol, count}] -> count
      [] -> 0
    end
  end

  @doc """
  List all active ticker streams with their subscriber counts.
  """
  @spec list_active_streams() :: [{String.t(), non_neg_integer()}]
  def list_active_streams do
    :ets.tab2list(@subscribers_table)
    |> Enum.filter(fn {_symbol, count} -> count > 0 end)
  end

  def via_tuple(symbol) do
    {:via, Registry, {DataCollector.StreamRegistry, {:ticker, String.upcase(symbol)}}}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, state)
        {:ok, %{state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        TickerStream: Failed to decode WebSocket message
        Symbol: #{state.symbol}
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error("TickerStream (#{state.symbol}): Too many decode errors, reconnecting...")

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
      TickerStream (#{state.symbol}): Max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      TickerStream (#{state.symbol}): Disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("""
    TickerStream (#{state.symbol}): Connected successfully
    Stream: #{state.stream}
    """)

    new_state = %{state | reconnect_attempts: 0, decode_errors: 0}
    {:ok, new_state}
  end

  # Private functions

  defp handle_message(%{"e" => "24hrMiniTicker"} = data, _state) do
    symbol = data["s"]
    price = data["c"]

    Logger.debug("TickerStream (#{symbol}): Price update #{price}")

    # Transform to standard ticker format compatible with existing code
    ticker = %{
      "e" => "24hrTicker",
      "s" => symbol,
      # Close/current price
      "c" => price,
      # Open price
      "o" => data["o"],
      # High
      "h" => data["h"],
      # Low
      "l" => data["l"],
      # Volume
      "v" => data["v"],
      # Quote volume
      "q" => data["q"]
    }

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "market:#{symbol}",
      {:ticker, ticker}
    )

    :ok
  end

  defp handle_message(data, state) do
    Logger.debug("TickerStream (#{state.symbol}): Unhandled message: #{inspect(data)}")
  end

  defp calculate_backoff(attempts) do
    base_backoff = Config.websocket(:initial_backoff)
    max_backoff = Config.websocket(:max_backoff)
    multiplier = Config.websocket(:backoff_multiplier)

    backoff = base_backoff * :math.pow(multiplier, attempts - 1)
    capped_backoff = min(trunc(backoff), max_backoff)

    jitter_range = trunc(capped_backoff * 0.2)
    jitter = :rand.uniform(jitter_range * 2 + 1) - jitter_range - 1

    max(capped_backoff + jitter, base_backoff)
  end
end
