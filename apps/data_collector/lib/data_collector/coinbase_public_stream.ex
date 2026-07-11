defmodule DataCollector.CoinbasePublicStream do
  @moduledoc """
  WebSocket client for Coinbase Advanced Trade's public `ticker` channel
  (`wss://advanced-trade-ws.coinbase.com` by default, see
  `docs/superpowers/notes/coinbase-api-verified.md` §4).

  Like `DataCollector.OKXPublicStream`/`DataCollector.KrakenPublicStream`
  (and unlike `DataCollector.TickerStream`'s one-process-per-Binance-symbol
  model), Coinbase multiplexes every channel subscription over a single
  connection via explicit `{"type":"subscribe",...}` messages, so this
  module keeps exactly one named connection process for the whole app and
  multiplexes symbol subscriptions on top of it, while still exposing the
  same `subscribe/1` / `unsubscribe/1` -> `{:ok, count}` reference-counted
  contract `TickerStream`/`OKXPublicStream`/`KrakenPublicStream` do, so
  `DataCollector.MarketStream` can present a uniform facade to
  `TradingEngine.Trader`.

  **Requires no credentials at all.** The `ticker` channel doesn't strictly
  need a `jwt` field (verified notes §4) — the `jwt` key is omitted from
  outgoing subscribe frames entirely rather than threading a fake/empty
  credential through this module:

      %{type: "subscribe", product_ids: [product_id], channel: "ticker"}

  **Must subscribe within 5 seconds of connecting** (verified notes §4 —
  the hardest deadline of the three adapters; OKX/Kraken tolerate much
  longer idle windows before disconnecting an unsubscribed connection).
  `handle_connect/2` itself can only return `{:ok, state}` — WebSockex's
  own callback contract has no `{:reply, frame, state}` option for
  `handle_connect/2` (only `handle_frame/2`/`handle_cast/2`/`handle_info/2`
  support replying with a frame), and `WebSockex.send_frame/2` raises
  `WebSockex.CallingSelfError` when called with `self()` as the target — so
  a literal zero-hop synchronous send from inside `handle_connect/2` is not
  an option this library exposes. This module therefore uses the same
  `send(self(), ...)` message-queue hop `OKXPublicStream`/
  `KrakenPublicStream` use, confirmed by reading `WebSockex`'s internal
  `websocket_loop/3` (a plain `receive` with a catch-all `msg ->
  common_handle({:handle_info, msg}, ...)` clause, no blocking I/O or sleep
  between callback invocations): a self-sent message is the very next
  mailbox message processed once `handle_connect/2` returns, landing in
  low single-digit milliseconds at worst — several orders of magnitude
  under the 5000ms deadline.

  Also subscribes to the `heartbeats` channel at connect
  (`%{type: "subscribe", channel: "heartbeats"}`, no `product_ids` needed)
  — Coinbase's heartbeat is a **push-based** keepalive that only flows once
  subscribed to it (verified notes §4), unlike OKX/Kraken's
  client-initiated ping, so this module sends **no** app-level ping frames
  of its own.

  Ticker routing: `%{"channel" => "ticker", "events" => events}` — the
  envelope is nested **two levels deep** (`events[].tickers[]`, not a flat
  `data[]` array like OKX/Kraken, verified notes §4, an explicit trap).
  `broadcast_ticker/1` reads `item["product_id"]`, resolves the concat
  symbol via `DataCollector.Coinbase.Products.to_concat/1` (an actual
  lookup this time, unlike Kraken's WS path — Coinbase's `product_id`
  always needs the hyphen-stripped translation and there's no
  "WS already speaks the right dialect" shortcut here).

  Every ticker push is normalized to the exact Binance `24hrTicker` map
  shape via `DataCollector.Coinbase.Normalize.ticker_event/2` and
  broadcast to `"market:\#{concat_symbol}"` as `{:ticker, map}`, matching
  `TickerStream`'s contract exactly (see plan §1).
  """
  use WebSockex
  require Logger

  alias DataCollector.Coinbase.{Normalize, Products}
  alias SharedData.Config

  @subscribers_table :coinbase_public_subscribers

  # Client API

  def start_link(_opts \\ []) do
    url = ws_public_url()

    initial_state = %{
      reconnect_attempts: 0,
      decode_errors: 0
    }

    case WebSockex.start_link(url, __MODULE__, initial_state, name: __MODULE__) do
      {:ok, pid} ->
        Logger.info("CoinbasePublicStream: started (#{url})")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Ensures the single Coinbase public-stream connection is running. Returns
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
  `"BTCUSD"`). Starts the shared connection if needed and sends the
  Coinbase `ticker` subscribe frame the first time a symbol gets a
  subscriber. Mirrors `DataCollector.OKXPublicStream.subscribe/1`'s
  contract.
  """
  @spec subscribe(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def subscribe(concat_symbol) do
    concat = String.upcase(concat_symbol)

    with {:ok, product_id} <- Products.to_product_id(concat),
         {:ok, pid} <- ensure_started() do
      count = :ets.update_counter(@subscribers_table, concat, 1, {concat, 0})

      if count == 1 do
        send_ticker_frame(pid, "subscribe", product_id)
      end

      Logger.info("CoinbasePublicStream (#{concat}): subscriber added, count: #{count}")
      {:ok, count}
    end
  end

  @doc """
  Unsubscribes from ticker updates for a Binance-style concat symbol.
  Sends the Coinbase `ticker` unsubscribe frame once the last subscriber
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

    Logger.info("CoinbasePublicStream (#{concat}): subscriber removed, count: #{count}")

    if count <= 0 do
      maybe_send_unsubscribe(concat)
      :ets.delete(@subscribers_table, concat)
    end

    {:ok, count}
  end

  defp maybe_send_unsubscribe(concat) do
    with pid when not is_nil(pid) <- Process.whereis(__MODULE__),
         {:ok, product_id} <- Products.to_product_id(concat) do
      send_ticker_frame(pid, "unsubscribe", product_id)
    end

    :ok
  end

  defp send_ticker_frame(pid, type, product_id) do
    frame = Jason.encode!(%{type: type, product_ids: [product_id], channel: "ticker"})
    WebSockex.send_frame(pid, {:text, frame})
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("CoinbasePublicStream: connected successfully")

    # Coinbase disconnects any connection that hasn't sent a subscribe
    # frame within 5 seconds (verified notes §4, the hardest deadline of
    # the three adapters). Queue both the heartbeats subscribe and any
    # ticker resubscribe as self-sent messages right away (see moduledoc
    # for why this message-hop lands well under the 5s window).
    send(self(), :subscribe_heartbeats)
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
        CoinbasePublicStream: failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error("CoinbasePublicStream: too many decode errors, reconnecting...")
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
  def handle_info(:subscribe_heartbeats, state) do
    frame = Jason.encode!(%{type: "subscribe", channel: "heartbeats"})
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_info(:resubscribe, state) do
    case subscribed_product_ids() do
      [] ->
        {:ok, state}

      product_ids ->
        Logger.info(
          "CoinbasePublicStream: re-subscribing #{length(product_ids)} symbol(s) after connect"
        )

        frame =
          Jason.encode!(%{type: "subscribe", product_ids: product_ids, channel: "ticker"})

        {:reply, {:text, frame}, state}
    end
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    attempts = state.reconnect_attempts + 1
    max_attempts = Config.websocket(:max_reconnect_attempts)

    if attempts >= max_attempts do
      Logger.error("""
      CoinbasePublicStream: max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      CoinbasePublicStream: disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  # Private functions

  defp subscribed_product_ids do
    @subscribers_table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {concat, count} when count > 0 ->
        case Products.to_product_id(concat) do
          {:ok, product_id} -> [product_id]
          {:error, _} -> []
        end

      _ ->
        []
    end)
  end

  defp handle_message(%{"channel" => "subscriptions"} = data) do
    Logger.debug("CoinbasePublicStream: subscriptions ack: #{inspect(data)}")
  end

  defp handle_message(%{"channel" => "heartbeats"}) do
    Logger.debug("CoinbasePublicStream: heartbeat")
  end

  defp handle_message(%{"channel" => "ticker", "events" => events}) do
    events
    |> Enum.flat_map(&(&1["tickers"] || []))
    |> Enum.each(&broadcast_ticker/1)
  end

  defp handle_message(%{"type" => "error"} = data) do
    Logger.error("CoinbasePublicStream: error: #{inspect(data)}")
  end

  defp handle_message(data) do
    Logger.debug("CoinbasePublicStream: unhandled message: #{inspect(data)}")
  end

  defp broadcast_ticker(%{"product_id" => product_id} = item) do
    case Products.to_concat(product_id) do
      {:ok, concat} ->
        ticker = Normalize.ticker_event(item, concat)

        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "market:#{concat}",
          {:ticker, ticker}
        )

      {:error, reason} ->
        Logger.warning(
          "CoinbasePublicStream: unknown product_id #{product_id}: #{inspect(reason)}"
        )
    end
  end

  defp broadcast_ticker(_other), do: :ok

  defp ws_public_url do
    Application.get_env(:data_collector, :coinbase, [])
    |> Keyword.get(:ws_public_url, "wss://advanced-trade-ws.coinbase.com")
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
