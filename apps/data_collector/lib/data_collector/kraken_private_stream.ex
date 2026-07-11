defmodule DataCollector.KrakenPrivateStream do
  @moduledoc """
  WebSocket client for Kraken's private `executions` channel
  (`wss://ws.kraken.com/v2` -- same URL as the public stream, see
  `docs/superpowers/notes/kraken-api-verified.md` §4: public and private
  channels share one connection endpoint, auth happens per-subscription
  via a `token` field rather than at the connection level), one connection
  per account.

  Auth differs from OKX's inline WS-login-op: Kraken requires a **REST
  call first** to mint a token (`POST /0/private/GetWebSocketsToken`, via
  `DataCollector.KrakenClient.get_ws_token/1`), then that token is passed
  directly in the `executions` subscribe frame -- there is no separate
  WS-level login op. On connect, `send(self(), :fetch_token_and_subscribe)`
  kicks this off asynchronously (mirrors OKX's `:do_login` pattern).

  **Token refresh** (verified notes §4 -- genuinely contradictory docs,
  resolved conservatively): Kraken's own docs disagree on whether a token
  expires while the WS connection + subscription stays alive. The safe
  choice taken here is to refresh proactively every 10 minutes
  (comfortably inside the documented 15-minute `expires: 900`) regardless
  of connection state, via a self-perpetuating `:refresh_token` timer, and
  to always fetch a fresh token on every (re)connect. A subscription-status
  push containing `"errorMessage": "Token is expired"` is treated as an
  immediate trigger to re-fetch-and-resubscribe too, as a belt-and-suspenders
  fallback independent of the timer.

  Execution pushes are normalized to the Binance `executionReport` shape
  via `DataCollector.Kraken.Normalize.execution_report/2` and broadcast to
  the `"order_updates"` topic as `{:execution_report, map}`, exactly
  matching `DataCollector.BinanceWebSocket`'s contract (see plan §1) so
  `TradingEngine.Trader` needs no changes to consume it. Symbol conversion
  on the incoming path is a pure `String.replace(symbol, "/", "")` (Kraken
  WS v2 already speaks `"BTC/USD"`-style symbols natively -- no
  `Kraken.Symbols` lookup needed, same reasoning as
  `DataCollector.KrakenPublicStream`).

  Processes are supervised by `DataCollector.KrakenPrivateSupervisor`
  (`DynamicSupervisor`) and named via `DataCollector.KrakenPrivateRegistry`
  (`Registry`), keyed by `account_id`. Never logs credentials or the WS
  token -- only `account_id` and Kraken's own (non-secret) event/error
  payloads.
  """
  use WebSockex
  require Logger

  alias DataCollector.{ExchangeClient, KrakenClient}
  alias DataCollector.Kraken.Normalize
  alias SharedData.{Config, Types}

  @ping_interval_ms 20_000
  @token_refresh_ms 10 * 60 * 1000

  # Client API

  @doc """
  Ensures a private executions-stream connection is running for
  `account_id`, starting one under `DataCollector.KrakenPrivateSupervisor`
  if needed. Idempotent -- safe to call every time a Trader for a Kraken
  account starts.
  """
  @spec ensure_started(Types.account_id(), ExchangeClient.credentials()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(account_id, credentials) do
    case Registry.lookup(DataCollector.KrakenPrivateRegistry, account_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               DataCollector.KrakenPrivateSupervisor,
               {__MODULE__, account_id: account_id, credentials: credentials}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end

  def start_link(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    credentials = Keyword.fetch!(opts, :credentials)

    url = ws_url()

    initial_state = %{
      account_id: account_id,
      credentials: credentials,
      token: nil,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    WebSockex.start_link(url, __MODULE__, initial_state, name: via_tuple(account_id))
  end

  defp via_tuple(account_id) do
    {:via, Registry, {DataCollector.KrakenPrivateRegistry, account_id}}
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("KrakenPrivateStream (account #{state.account_id}): connected, fetching WS token")
    schedule_ping()
    schedule_token_refresh()
    send(self(), :fetch_token_and_subscribe)
    {:ok, %{state | token: nil, reconnect_attempts: 0, decode_errors: 0}}
  end

  @impl true
  def handle_info(:fetch_token_and_subscribe, state) do
    case KrakenClient.get_ws_token(state.credentials) do
      {:ok, token} ->
        Logger.info(
          "KrakenPrivateStream (account #{state.account_id}): got WS token, subscribing to executions"
        )

        {:reply, {:text, subscribe_executions_frame(token)}, %{state | token: token}}

      {:error, reason} ->
        Logger.error(
          "KrakenPrivateStream (account #{state.account_id}): failed to fetch WS token: #{inspect(reason)}"
        )

        {:ok, state}
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    schedule_token_refresh()
    send(self(), :fetch_token_and_subscribe)
    {:ok, state}
  end

  @impl true
  def handle_info(:send_ping, state) do
    schedule_ping()
    frame = Jason.encode!(%{method: "ping", req_id: System.unique_integer([:positive])})
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, %{state | decode_errors: 0})

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        KrakenPrivateStream (account #{state.account_id}): failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error(
            "KrakenPrivateStream (account #{state.account_id}): too many decode errors, reconnecting..."
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
      KrakenPrivateStream (account #{state.account_id}): max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      KrakenPrivateStream (account #{state.account_id}): disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      # token reset to nil here too; handle_connect re-triggers a fresh
      # token fetch + re-subscribe on reconnect, per verified notes §4's
      # "always fetch a fresh token on reconnect" recommendation.
      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0, token: nil}
      {:reconnect, new_state}
    end
  end

  # Private functions

  defp handle_message(%{"errorMessage" => "Token is expired"} = data, state) do
    Logger.warning(
      "KrakenPrivateStream (account #{state.account_id}): WS token expired, re-fetching: #{inspect(Map.delete(data, "token"))}"
    )

    send(self(), :fetch_token_and_subscribe)
    {:ok, state}
  end

  defp handle_message(%{"method" => "pong"} = data, state) do
    Logger.debug("KrakenPrivateStream (account #{state.account_id}): pong: #{inspect(data)}")
    {:ok, state}
  end

  defp handle_message(%{"channel" => "heartbeat"}, state) do
    {:ok, state}
  end

  defp handle_message(%{"method" => method} = data, state)
       when method in ~w(subscribe unsubscribe) do
    Logger.debug(
      "KrakenPrivateStream (account #{state.account_id}): #{method} ack: #{inspect(Map.delete(data, "token"))}"
    )

    {:ok, state}
  end

  defp handle_message(%{"channel" => "executions", "data" => items}, state) do
    Enum.each(items, &broadcast_execution_report(&1, state.account_id))
    {:ok, state}
  end

  defp handle_message(data, state) do
    Logger.debug(
      "KrakenPrivateStream (account #{state.account_id}): unhandled message: #{inspect(data)}"
    )

    {:ok, state}
  end

  defp broadcast_execution_report(%{"symbol" => symbol} = item, _account_id) do
    concat = String.replace(symbol, "/", "")
    report = Normalize.execution_report(item, concat)

    Phoenix.PubSub.broadcast(
      BinanceSystem.PubSub,
      "order_updates",
      {:execution_report, report}
    )
  end

  defp broadcast_execution_report(_other, _account_id), do: :ok

  defp subscribe_executions_frame(token) do
    Jason.encode!(%{
      method: "subscribe",
      params: %{channel: "executions", token: token, snap_orders: true, snap_trades: false}
    })
  end

  defp schedule_ping do
    Process.send_after(self(), :send_ping, @ping_interval_ms)
  end

  defp schedule_token_refresh do
    Process.send_after(self(), :refresh_token, @token_refresh_ms)
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
