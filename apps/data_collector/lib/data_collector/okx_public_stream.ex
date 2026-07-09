defmodule DataCollector.OKXPublicStream do
  @moduledoc """
  WebSocket client for OKX's public `tickers` channel
  (`wss://ws.okx.com:8443/ws/v5/public`, or the `wspap.okx.com` demo host —
  see `docs/superpowers/notes/okx-api-verified.md` §8).

  Unlike `DataCollector.TickerStream` (one WebSockex process per Binance
  symbol, subscription encoded in the URL path), OKX multiplexes every
  channel subscription over a single connection via explicit
  `{"op":"subscribe",...}` messages. This module therefore keeps exactly
  one named connection process for the whole app and multiplexes symbol
  subscriptions on top of it, while still exposing the same
  `subscribe/1` / `unsubscribe/1` -> `{:ok, count}` reference-counted
  contract `TickerStream` does, so `DataCollector.MarketStream` can present
  a uniform facade to `TradingEngine.Trader`.

  Every push is normalized to the exact Binance `24hrTicker` map shape via
  `DataCollector.OKX.Normalize.ticker_event/2` and broadcast to
  `"market:\#{concat_symbol}"` as `{:ticker, map}`, matching
  `TickerStream`'s contract exactly (see plan §1).
  """
  use WebSockex
  require Logger

  alias DataCollector.OKX.{Normalize, Symbols}
  alias SharedData.Config

  @subscribers_table :okx_public_subscribers
  @ping_interval_ms 20_000

  # Client API

  def start_link(_opts \\ []) do
    url = ws_public_url()

    initial_state = %{
      reconnect_attempts: 0,
      decode_errors: 0
    }

    case WebSockex.start_link(url, __MODULE__, initial_state, name: __MODULE__) do
      {:ok, pid} ->
        Logger.info("OKXPublicStream: started (#{url})")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Ensures the single OKX public-stream connection is running. Returns
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
  `"BTCUSDT"`). Starts the shared connection if needed and sends the OKX
  `tickers` subscribe op the first time a symbol gets a subscriber.
  Mirrors `DataCollector.TickerStream.subscribe/1`'s contract.
  """
  @spec subscribe(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def subscribe(concat_symbol) do
    concat = String.upcase(concat_symbol)

    with {:ok, inst_id} <- Symbols.to_inst_id(concat),
         {:ok, pid} <- ensure_started() do
      count = :ets.update_counter(@subscribers_table, concat, 1, {concat, 0})

      if count == 1 do
        send_op(pid, "subscribe", inst_id)
      end

      Logger.info("OKXPublicStream (#{concat}): subscriber added, count: #{count}")
      {:ok, count}
    end
  end

  @doc """
  Unsubscribes from ticker updates for a Binance-style concat symbol.
  Sends the OKX `tickers` unsubscribe op once the last subscriber leaves.
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

    Logger.info("OKXPublicStream (#{concat}): subscriber removed, count: #{count}")

    if count <= 0 do
      maybe_send_unsubscribe(concat)
      :ets.delete(@subscribers_table, concat)
    end

    {:ok, count}
  end

  defp maybe_send_unsubscribe(concat) do
    with pid when not is_nil(pid) <- Process.whereis(__MODULE__),
         {:ok, inst_id} <- Symbols.to_inst_id(concat) do
      send_op(pid, "unsubscribe", inst_id)
    end

    :ok
  end

  defp send_op(pid, op, inst_id) do
    frame = Jason.encode!(%{op: op, args: [%{channel: "tickers", instId: inst_id}]})
    WebSockex.send_frame(pid, {:text, frame})
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("OKXPublicStream: connected successfully")
    schedule_ping()
    # OKX multiplexes all subscriptions over one connection and does NOT
    # preserve them across reconnects. Re-subscribe every symbol that still
    # has active subscribers so ticker broadcasts resume after any reconnect
    # (and to cover the cold-start race where subscribe/1 may send its op
    # before this connect fires).
    send(self(), :resubscribe)
    {:ok, %{state | reconnect_attempts: 0, decode_errors: 0}}
  end

  @impl true
  def handle_frame({:text, "pong"}, state), do: {:ok, state}

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data)
        {:ok, %{state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        OKXPublicStream: failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error("OKXPublicStream: too many decode errors, reconnecting...")
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
    args =
      @subscribers_table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {concat, count} when count > 0 ->
          case Symbols.to_inst_id(concat) do
            {:ok, inst_id} -> [%{channel: "tickers", instId: inst_id}]
            {:error, _} -> []
          end

        _ ->
          []
      end)

    case args do
      [] ->
        {:ok, state}

      _ ->
        Logger.info("OKXPublicStream: re-subscribing #{length(args)} symbol(s) after connect")
        frame = Jason.encode!(%{op: "subscribe", args: args})
        {:reply, {:text, frame}, state}
    end
  end

  @impl true
  def handle_info(:send_ping, state) do
    schedule_ping()
    {:reply, {:text, "ping"}, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    attempts = state.reconnect_attempts + 1
    max_attempts = Config.websocket(:max_reconnect_attempts)

    if attempts >= max_attempts do
      Logger.error("""
      OKXPublicStream: max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      OKXPublicStream: disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0}
      {:reconnect, new_state}
    end
  end

  # Private functions

  defp handle_message(%{"event" => event} = data) when event in ~w(subscribe unsubscribe error) do
    Logger.debug("OKXPublicStream: #{event} ack: #{inspect(data)}")
  end

  defp handle_message(%{"arg" => %{"channel" => "tickers"}, "data" => items}) do
    Enum.each(items, &broadcast_ticker/1)
  end

  defp handle_message(data) do
    Logger.debug("OKXPublicStream: unhandled message: #{inspect(data)}")
  end

  defp broadcast_ticker(%{"instId" => inst_id} = item) do
    case Symbols.to_concat(inst_id) do
      {:ok, concat} ->
        ticker = Normalize.ticker_event(item, concat)

        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "market:#{concat}",
          {:ticker, ticker}
        )

      {:error, reason} ->
        Logger.warning("OKXPublicStream: unknown instId #{inst_id}: #{inspect(reason)}")
    end
  end

  defp broadcast_ticker(_other), do: :ok

  defp schedule_ping do
    Process.send_after(self(), :send_ping, @ping_interval_ms)
  end

  defp ws_public_url do
    Application.get_env(:data_collector, :okx, [])
    |> Keyword.get(:ws_public_url, "wss://ws.okx.com:8443/ws/v5/public")
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
