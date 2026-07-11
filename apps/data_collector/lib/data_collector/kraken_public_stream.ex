defmodule DataCollector.KrakenPublicStream do
  @moduledoc """
  WebSocket client for Kraken's public `ticker` channel
  (`wss://ws.kraken.com/v2` by default, see
  `docs/superpowers/notes/kraken-api-verified.md` §4).

  Like `DataCollector.OKXPublicStream` (and unlike
  `DataCollector.TickerStream`'s one-process-per-Binance-symbol model),
  Kraken multiplexes every channel subscription over a single connection
  via explicit `{"method":"subscribe",...}` messages, so this module keeps
  exactly one named connection process for the whole app and multiplexes
  symbol subscriptions on top of it, while still exposing the same
  `subscribe/1` / `unsubscribe/1` -> `{:ok, count}` reference-counted
  contract `TickerStream`/`OKXPublicStream` do, so
  `DataCollector.MarketStream` can present a uniform facade to
  `TradingEngine.Trader`.

  Frame shapes differ from OKX's `{"op":...,"args":[...]}`:

      # subscribe / unsubscribe
      %{method: "subscribe", params: %{channel: "ticker", symbol: [ws_symbol]}}

  `ws_symbol` (e.g. `"BTC/USD"`) comes from
  `DataCollector.Kraken.Symbols.to_ws_symbol/1` on the *outgoing* subscribe
  path only. Incoming ticker pushes already speak `"BTC/USD"`-style
  symbols directly (WS v2 has its own clean namespace, no `XBT`/`XDG`
  substitution needed -- verified notes §3), so routing a push back to a
  Binance-style concat symbol is a **pure string op**
  (`String.replace(symbol, "/", "")`), deliberately *not* a
  `Kraken.Symbols` lookup.

  Kraken's app-level ping is a JSON object (`{"method":"ping","req_id":_}`,
  server replies `{"method":"pong",...}`), unlike OKX's bare `"ping"`
  string -- see verified notes §4. Kraken also pushes an automatic
  `{"channel":"heartbeat"}` message roughly once a second whenever no other
  channel traffic is flowing; both pongs and heartbeats are just liveness
  signals, logged at `:debug` and otherwise ignored (verified notes §4
  flags there's no documented hard disconnect-timeout, so the ping-if-quiet
  behavior here is a defensive default, not a strict protocol requirement).

  Every ticker push is normalized to the exact Binance `24hrTicker` map
  shape via `DataCollector.Kraken.Normalize.ticker_event/2` and broadcast
  to `"market:\#{concat_symbol}"` as `{:ticker, map}`, matching
  `TickerStream`'s contract exactly (see plan §1).
  """
  use WebSockex
  require Logger

  alias DataCollector.Kraken.{Normalize, Symbols}
  alias SharedData.Config

  @subscribers_table :kraken_public_subscribers
  @ping_interval_ms 20_000

  # Client API

  def start_link(_opts \\ []) do
    url = ws_url()

    initial_state = %{
      reconnect_attempts: 0,
      decode_errors: 0
    }

    case WebSockex.start_link(url, __MODULE__, initial_state, name: __MODULE__) do
      {:ok, pid} ->
        Logger.info("KrakenPublicStream: started (#{url})")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Ensures the single Kraken public-stream connection is running. Returns
  `{:ok, pid}` whether it was already running or just started.
  """
  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil -> start_link()
      pid -> {:ok, pid}
    end
  end

  @doc """
  Subscribes to ticker updates for a Binance-style concat symbol (e.g.
  `"BTCUSD"`). Starts the shared connection if needed and sends the Kraken
  `ticker` subscribe frame the first time a symbol gets a subscriber.
  Mirrors `DataCollector.OKXPublicStream.subscribe/1`'s contract.
  """
  @spec subscribe(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def subscribe(concat_symbol) do
    concat = String.upcase(concat_symbol)

    with {:ok, ws_symbol} <- Symbols.to_ws_symbol(concat),
         {:ok, pid} <- ensure_started() do
      count = :ets.update_counter(@subscribers_table, concat, 1, {concat, 0})

      if count == 1 do
        send_frame(pid, "subscribe", ws_symbol)
      end

      Logger.info("KrakenPublicStream (#{concat}): subscriber added, count: #{count}")
      {:ok, count}
    end
  end

  @doc """
  Unsubscribes from ticker updates for a Binance-style concat symbol.
  Sends the Kraken `ticker` unsubscribe frame once the last subscriber
  leaves.
  """
  @spec unsubscribe(String.t()) :: {:ok, non_neg_integer()}
  def unsubscribe(concat_symbol) do
    concat = String.upcase(concat_symbol)

    count =
      case :ets.lookup(@subscribers_table, concat) do
        [{^concat, current}] when current > 0 ->
          :ets.update_counter(@subscribers_table, concat, -1)

        _ ->
          0
      end

    Logger.info("KrakenPublicStream (#{concat}): subscriber removed, count: #{count}")

    if count <= 0 do
      maybe_send_unsubscribe(concat)
      :ets.delete(@subscribers_table, concat)
    end

    {:ok, count}
  end

  defp maybe_send_unsubscribe(concat) do
    with pid when not is_nil(pid) <- Process.whereis(__MODULE__),
         {:ok, ws_symbol} <- Symbols.to_ws_symbol(concat) do
      send_frame(pid, "unsubscribe", ws_symbol)
    end

    :ok
  end

  defp send_frame(pid, method, ws_symbol) do
    frame = Jason.encode!(%{method: method, params: %{channel: "ticker", symbol: [ws_symbol]}})
    WebSockex.send_frame(pid, {:text, frame})
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("KrakenPublicStream: connected successfully")
    schedule_ping()
    # Kraken doesn't preserve subscriptions across reconnects either
    # (undocumented either way -- treated the same defensive way as the OKX
    # precedent). Re-subscribe every symbol that still has active
    # subscribers so ticker broadcasts resume after any reconnect (and to
    # cover the cold-start race where subscribe/1 may send its frame before
    # this connect fires).
    send(self(), :resubscribe)
    {:ok, %{state | reconnect_attempts: 0, decode_errors: 0}}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data)
        {:ok, %{state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        KrakenPublicStream: failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error("KrakenPublicStream: too many decode errors, reconnecting...")
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
  def handle_info(:resubscribe, state) do
    ws_symbols =
      @subscribers_table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {concat, count} when count > 0 ->
          case Symbols.to_ws_symbol(concat) do
            {:ok, ws_symbol} -> [ws_symbol]
            {:error, _} -> []
          end

        _ ->
          []
      end)

    case ws_symbols do
      [] ->
        {:ok, state}

      _ ->
        Logger.info(
          "KrakenPublicStream: re-subscribing #{length(ws_symbols)} symbol(s) after connect"
        )

        frame =
          Jason.encode!(%{method: "subscribe", params: %{channel: "ticker", symbol: ws_symbols}})

        {:reply, {:text, frame}, state}
    end
  end

  @impl true
  def handle_info(:send_ping, state) do
    schedule_ping()
    frame = Jason.encode!(%{method: "ping", req_id: System.unique_integer([:positive])})
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    attempts = state.reconnect_attempts + 1
    max_attempts = Config.websocket(:max_reconnect_attempts)

    if attempts >= max_attempts do
      Logger.error("""
      KrakenPublicStream: max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      KrakenPublicStream: disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  # Private functions

  defp handle_message(%{"method" => "pong"} = data) do
    Logger.debug("KrakenPublicStream: pong: #{inspect(data)}")
  end

  defp handle_message(%{"channel" => "heartbeat"}) do
    :ok
  end

  defp handle_message(%{"channel" => "ticker", "data" => items}) do
    Enum.each(items, &broadcast_ticker/1)
  end

  defp handle_message(%{"method" => method} = data) when method in ~w(subscribe unsubscribe) do
    Logger.debug("KrakenPublicStream: #{method} ack: #{inspect(data)}")
  end

  defp handle_message(data) do
    Logger.debug("KrakenPublicStream: unhandled message: #{inspect(data)}")
  end

  defp broadcast_ticker(%{"symbol" => symbol} = item) do
    concat = String.replace(symbol, "/", "")
    ticker = Normalize.ticker_event(item, concat)

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "market:#{concat}",
      {:ticker, ticker}
    )
  end

  defp broadcast_ticker(_other), do: :ok

  defp schedule_ping do
    Process.send_after(self(), :send_ping, @ping_interval_ms)
  end

  defp ws_url do
    Application.get_env(:data_collector, :kraken, [])
    |> Keyword.get(:ws_url, "wss://ws.kraken.com/v2")
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
