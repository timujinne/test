defmodule DataCollector.CoinbasePrivateStream do
  @moduledoc """
  WebSocket client for Coinbase Advanced Trade's private `user` channel
  (`wss://advanced-trade-ws-user.coinbase.com` by default, see
  `docs/superpowers/notes/coinbase-api-verified.md` §4), one connection per
  account.

  Auth differs from every other adapter here: the JWT is a field **inside**
  the `subscribe` message itself, not a separate login op (OKX) or a
  pre-fetched REST token (Kraken) -- and because a Coinbase WS JWT's `exp`
  is only 2 minutes out, **a fresh JWT must be minted right before every
  send that needs one**, never cached/reused across sends or reconnects
  (verified notes §4). On connect:

      %{type: "subscribe", product_ids: [], channel: "user", jwt: Coinbase.Auth.build_ws_jwt(credentials)}

  (`product_ids: []` subscribes to all products for the account -- verified
  notes §4's canonical example doesn't scope `user` by product.) Also
  subscribes to `heartbeats` on this connection (same push-based-keepalive
  reasoning as `DataCollector.CoinbasePublicStream` -- no client ping is
  sent). Both subscribes are dispatched via the same
  `send(self(), ...)` message-hop pattern as `CoinbasePublicStream` (see
  its moduledoc for why `handle_connect/2` can't reply with a frame
  directly), which comfortably clears Coinbase's 5-second
  must-subscribe-or-disconnect deadline.

  ## `last_cum_qty` -- per-order cumulative-fill tracking, reset on reconnect

  The `user` channel's order events only carry **cumulative** fill data
  (`cumulative_quantity`), not a per-fill delta or the original order size
  (verified notes §4, `DataCollector.Coinbase.Normalize` moduledoc). State
  carries `last_cum_qty :: %{order_id => Decimal.t()}`, seeded to
  `Decimal.new(0)` the first time an order_id is seen. On every reconnect
  this map resets to `%{}` -- an accepted, documented limitation carried
  over from Task 6's `Normalize.execution_report/3`, not a bug: a fill that
  straddles a reconnect will report a `"l"` (last fill qty) equal to the
  full post-reconnect `cumulative_quantity` rather than just the new delta.

  Order-event routing: `%{"channel" => "user", "events" => events}` ->
  `Enum.flat_map(events, & &1["orders"])`, each item resolves its concat
  symbol via `DataCollector.Coinbase.Products.to_concat/1` on
  `item["product_id"]`, looks up `prev_cum_qty` from `state.last_cum_qty`,
  calls `DataCollector.Coinbase.Normalize.execution_report/3`, updates
  `state.last_cum_qty[order_id]`, and broadcasts `{:execution_report,
  report}` to the `"order_updates"` topic -- exactly matching
  `DataCollector.BinanceWebSocket`'s contract so `TradingEngine.Trader`
  needs no changes to consume it.

  Processes are supervised by `DataCollector.CoinbasePrivateSupervisor`
  (`DynamicSupervisor`) and named via `DataCollector.CoinbasePrivateRegistry`
  (`Registry`), keyed by `account_id`. Never logs `credentials`, the built
  JWT, or the token/key material in any form -- `state.last_cum_qty`'s
  keys/values (order ids and trade sizes) are not secrets and may appear in
  `:debug` logs, but the hard rule is specifically about api keys/secrets/
  PEM/JWTs/tokens, not trade sizes (see spec Task 7).
  """
  use WebSockex
  require Logger

  alias DataCollector.Coinbase.{Auth, Normalize, Products}
  alias DataCollector.ExchangeClient
  alias SharedData.{Config, Types}

  # Client API

  @doc """
  Ensures a private user-stream connection is running for `account_id`,
  starting one under `DataCollector.CoinbasePrivateSupervisor` if needed.
  Idempotent -- safe to call every time a Trader for a Coinbase account
  starts.
  """
  @spec ensure_started(Types.account_id(), ExchangeClient.credentials()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(account_id, credentials) do
    case Registry.lookup(DataCollector.CoinbasePrivateRegistry, account_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               DataCollector.CoinbasePrivateSupervisor,
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

    url = ws_user_url()

    initial_state = %{
      account_id: account_id,
      credentials: credentials,
      last_cum_qty: %{},
      reconnect_attempts: 0,
      decode_errors: 0
    }

    WebSockex.start_link(url, __MODULE__, initial_state, name: via_tuple(account_id))
  end

  defp via_tuple(account_id) do
    {:via, Registry, {DataCollector.CoinbasePrivateRegistry, account_id}}
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("CoinbasePrivateStream (account #{state.account_id}): connected, subscribing")

    # See DataCollector.CoinbasePublicStream's moduledoc for why this
    # message-hop pattern is used instead of replying directly from
    # handle_connect/2, and why it still comfortably clears Coinbase's 5s
    # must-subscribe-or-disconnect deadline.
    send(self(), :subscribe_heartbeats)
    send(self(), :subscribe_user)

    # last_cum_qty resets to %{} here too -- Coinbase's user channel gives
    # no snapshot-replay guarantee across reconnects worth relying on, so
    # fill deltas restart from zero (see moduledoc).
    {:ok, %{state | last_cum_qty: %{}, reconnect_attempts: 0, decode_errors: 0}}
  end

  @impl true
  def handle_info(:subscribe_heartbeats, state) do
    frame = Jason.encode!(%{type: "subscribe", channel: "heartbeats"})
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_info(:subscribe_user, state) do
    frame =
      Jason.encode!(%{
        type: "subscribe",
        product_ids: [],
        channel: "user",
        jwt: Auth.build_ws_jwt(state.credentials)
      })

    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, data} ->
        new_state = handle_message(data, state)
        {:ok, %{new_state | decode_errors: 0}}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("""
        CoinbasePrivateStream (account #{state.account_id}): failed to decode WebSocket message
        Error: #{inspect(error)}
        Raw message (first 200 chars): #{String.slice(msg, 0, 200)}
        """)

        new_state = %{state | decode_errors: state.decode_errors + 1}

        if new_state.decode_errors > 10 do
          Logger.error(
            "CoinbasePrivateStream (account #{state.account_id}): too many decode errors, reconnecting..."
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
      CoinbasePrivateStream (account #{state.account_id}): max reconnect attempts reached (#{attempts}/#{max_attempts})
      Reason: #{inspect(reason)}
      Giving up reconnection
      """)

      {:stop, {:shutdown, :max_reconnects_reached}, state}
    else
      backoff_ms = calculate_backoff(attempts)

      Logger.warning("""
      CoinbasePrivateStream (account #{state.account_id}): disconnected: #{inspect(reason)}
      Reconnecting in #{backoff_ms}ms (attempt #{attempts}/#{max_attempts})
      """)

      Process.sleep(backoff_ms)

      # last_cum_qty reset to %{} here too; handle_connect/2 re-triggers a
      # fresh subscribe (with a freshly-minted JWT) on reconnect.
      new_state = %{
        state
        | reconnect_attempts: attempts,
          decode_errors: 0,
          last_cum_qty: %{}
      }

      {:reconnect, new_state}
    end
  end

  # Private functions

  defp handle_message(%{"channel" => "subscriptions"} = data, state) do
    Logger.debug(
      "CoinbasePrivateStream (account #{state.account_id}): subscriptions ack: #{inspect(data)}"
    )

    state
  end

  defp handle_message(%{"channel" => "heartbeats"}, state) do
    Logger.debug("CoinbasePrivateStream (account #{state.account_id}): heartbeat")
    state
  end

  defp handle_message(%{"channel" => "user", "events" => events}, state) do
    events
    |> Enum.flat_map(&(&1["orders"] || []))
    |> Enum.reduce(state, &handle_order_event/2)
  end

  defp handle_message(%{"type" => "error"} = data, state) do
    Logger.error("CoinbasePrivateStream (account #{state.account_id}): error: #{inspect(data)}")

    state
  end

  defp handle_message(data, state) do
    Logger.debug(
      "CoinbasePrivateStream (account #{state.account_id}): unhandled message: #{inspect(data)}"
    )

    state
  end

  defp handle_order_event(%{"product_id" => product_id, "order_id" => order_id} = item, state) do
    case Products.to_concat(product_id) do
      {:ok, concat} ->
        prev_cum_qty = Map.get(state.last_cum_qty, order_id, Decimal.new(0))
        report = Normalize.execution_report(item, concat, prev_cum_qty)

        Phoenix.PubSub.broadcast(
          BinanceSystem.PubSub,
          "order_updates",
          {:execution_report, report}
        )

        cum_qty = Decimal.new(item["cumulative_quantity"])
        %{state | last_cum_qty: Map.put(state.last_cum_qty, order_id, cum_qty)}

      {:error, reason} ->
        Logger.warning(
          "CoinbasePrivateStream (account #{state.account_id}): unknown product_id #{product_id}: #{inspect(reason)}"
        )

        state
    end
  end

  defp handle_order_event(_other, state), do: state

  defp ws_user_url do
    Application.get_env(:data_collector, :coinbase, [])
    |> Keyword.get(:ws_user_url, "wss://advanced-trade-ws-user.coinbase.com")
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
