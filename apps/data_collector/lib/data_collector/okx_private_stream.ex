defmodule DataCollector.OKXPrivateStream do
  @moduledoc """
  WebSocket client for OKX's private `orders` channel
  (`wss://ws.okx.com:8443/ws/v5/private`, or the `wspap.okx.com` demo host —
  see `docs/superpowers/notes/okx-api-verified.md` §8-9), one connection per
  account.

  On connect: sends the WS login op (HMAC-SHA256 signature over
  `timestamp <> "GET" <> "/users/self/verify"`, unix-seconds timestamp —
  **not** the REST millisecond-ISO8601 format, see verified notes §9), then
  on a successful login ack subscribes to the `orders` channel for
  `instType: "SPOT"` (all SPOT orders for the account, un-scoped by symbol).
  Every order push is normalized to the Binance `executionReport` shape via
  `DataCollector.OKX.Normalize.execution_report/2` and broadcast to the
  `"order_updates"` topic as `{:execution_report, map}`, exactly matching
  `DataCollector.BinanceWebSocket`'s contract (see plan §1) so
  `TradingEngine.Trader` needs no changes to consume it.

  Processes are supervised by `DataCollector.OKXPrivateSupervisor`
  (`DynamicSupervisor`) and named via `DataCollector.OKXPrivateRegistry`
  (`Registry`), keyed by `account_id`. Never logs credentials — only
  `account_id` and OKX's own (non-secret) event/error payloads.
  """
  use WebSockex
  require Logger

  alias DataCollector.ExchangeClient
  alias DataCollector.OKX.{Auth, Normalize, Symbols}
  alias SharedData.{Config, Types}

  @ping_interval_ms 20_000

  # Client API

  @doc """
  Ensures a private order-stream connection is running for `account_id`,
  starting one under `DataCollector.OKXPrivateSupervisor` if needed.
  Idempotent — safe to call every time a Trader for an OKX account starts.
  """
  @spec ensure_started(Types.account_id(), ExchangeClient.credentials()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(account_id, credentials) do
    case Registry.lookup(DataCollector.OKXPrivateRegistry, account_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               DataCollector.OKXPrivateSupervisor,
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

    url = ws_private_url()

    initial_state = %{
      account_id: account_id,
      credentials: credentials,
      logged_in?: false,
      reconnect_attempts: 0,
      decode_errors: 0
    }

    WebSockex.start_link(url, __MODULE__, initial_state, name: via_tuple(account_id))
  end

  defp via_tuple(account_id) do
    {:via, Registry, {DataCollector.OKXPrivateRegistry, account_id}}
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("OKXPrivateStream (account #{state.account_id}): connected, logging in")
    schedule_ping()
    send(self(), :do_login)
    {:ok, %{state | logged_in?: false, reconnect_attempts: 0, decode_errors: 0}}
  end

  @impl true
  def handle_info(:do_login, state) do
    {:reply, {:text, login_frame(state.credentials)}, state}
  end

  @impl true
  def handle_info(:send_ping, state) do
    schedule_ping()
    {:reply, {:text, "ping"}, state}
  end

  @impl true
  def handle_frame({:text, "pong"}, state), do: {:ok, state}

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        handle_message(data, %{state | decode_errors: 0})

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        OKXPrivateStream (account #{state.account_id}): failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error(
            "OKXPrivateStream (account #{state.account_id}): too many decode errors, reconnecting..."
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
      OKXPrivateStream (account #{state.account_id}): max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      OKXPrivateStream (account #{state.account_id}): disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      # logged_in? reset to false here too; handle_connect re-triggers login
      # + re-subscribe on reconnect, since OKX doesn't preserve session state
      # across reconnects (verified notes §9).
      new_state = %{state | reconnect_attempts: attempts, decode_errors: 0, logged_in?: false}
      {:reconnect, new_state}
    end
  end

  # Private functions

  defp handle_message(%{"event" => "login", "code" => "0"}, state) do
    Logger.info("OKXPrivateStream (account #{state.account_id}): login ok, subscribing to orders")

    {:reply, {:text, subscribe_orders_frame()}, %{state | logged_in?: true}}
  end

  defp handle_message(%{"event" => "login"} = data, state) do
    Logger.error("OKXPrivateStream (account #{state.account_id}): login failed: #{inspect(data)}")

    {:ok, state}
  end

  defp handle_message(%{"event" => event} = data, state)
       when event in ~w(subscribe unsubscribe error) do
    Logger.debug("OKXPrivateStream (account #{state.account_id}): #{event} ack: #{inspect(data)}")
    {:ok, state}
  end

  defp handle_message(%{"arg" => %{"channel" => "orders"}, "data" => items}, state) do
    Enum.each(items, &broadcast_execution_report(&1, state.account_id))
    {:ok, state}
  end

  defp handle_message(data, state) do
    Logger.debug(
      "OKXPrivateStream (account #{state.account_id}): unhandled message: #{inspect(data)}"
    )

    {:ok, state}
  end

  defp broadcast_execution_report(%{"instId" => inst_id} = item, account_id) do
    case Symbols.to_concat(inst_id) do
      {:ok, concat} ->
        report = Normalize.execution_report(item, concat)

        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "order_updates",
          {:execution_report, report}
        )

      {:error, reason} ->
        Logger.warning(
          "OKXPrivateStream (account #{account_id}): unknown instId #{inst_id}: #{inspect(reason)}"
        )
    end
  end

  defp broadcast_execution_report(_other, _account_id), do: :ok

  defp login_frame(%{api_key: api_key, secret_key: secret_key, passphrase: passphrase}) do
    ts = Integer.to_string(System.system_time(:second))
    sig = Auth.sign(secret_key, ts, "GET", "/users/self/verify", "")

    Jason.encode!(%{
      op: "login",
      args: [%{apiKey: api_key, passphrase: passphrase, timestamp: ts, sign: sig}]
    })
  end

  defp subscribe_orders_frame do
    Jason.encode!(%{op: "subscribe", args: [%{channel: "orders", instType: "SPOT"}]})
  end

  defp schedule_ping do
    Process.send_after(self(), :send_ping, @ping_interval_ms)
  end

  defp ws_private_url do
    Application.get_env(:data_collector, :okx, [])
    |> Keyword.get(:ws_private_url, "wss://ws.okx.com:8443/ws/v5/private")
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
