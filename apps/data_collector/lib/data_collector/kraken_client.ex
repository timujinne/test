defmodule DataCollector.KrakenClient do
  @moduledoc """
  HTTP client for the Kraken Spot REST API, implementing
  `DataCollector.ExchangeClient`.

  Every private-endpoint payload this module returns (and accepts, for
  `create_order/2`) is normalized to/from Binance's exact key contracts via
  `DataCollector.Kraken.Normalize`, the same "normalize everything into
  Binance's shape" strategy the OKX adapter uses. Symbol translation
  between Binance-style concat symbols (`"BTCUSD"`) and Kraken pair
  identifiers goes through `DataCollector.Kraken.Symbols`.

  Kraken's private REST API is **POST-only** (`nonce`/`otp` are POST-body
  params, not query params — see
  `docs/superpowers/notes/kraken-api-verified.md` §1) — there is no `GET`
  helper here, unlike `DataCollector.OKXClient`.

  All calls go through `DataCollector.CircuitBreaker` under the
  `:kraken_api` circuit, same pattern as `DataCollector.OKXClient`'s
  `:okx_api`.
  """
  @behaviour DataCollector.ExchangeClient

  require Logger

  alias DataCollector.{CircuitBreaker, ExchangeClient}
  alias DataCollector.Kraken.{Auth, Normalize, Symbols}
  alias SharedData.Types

  @doc """
  Account balances. `POST /0/private/BalanceEx` (not plain `Balance`,
  which has no free/locked split — verified notes §2) -> Binance-shaped
  `%{"balances" => [%{"asset" => _, "free" => _, "locked" => _}]}`.
  """
  @impl true
  @spec get_account(ExchangeClient.credentials()) :: Types.result(map())
  def get_account(credentials) do
    with {:ok, result} <- post(credentials, "/0/private/BalanceEx", %{}) do
      {:ok, Normalize.account_response(result)}
    end
  end

  @doc """
  Places an order. `order_params` is Binance-format (as built by the
  strategy layer). Places via `POST /0/private/AddOrder`. Unlike OKX, this
  does **not** re-fetch the order afterward — the placement ack alone
  carries no fill detail, and Kraken's `OpenOrders` can't be relied on for
  a just-filled market order (it drops out of the open set immediately).
  The Binance-shaped response is built directly from the known request
  and the ack's `txid` (see `Normalize.order_response_from_placement/2`).
  """
  @impl true
  @spec create_order(ExchangeClient.credentials(), Types.order_params()) ::
          Types.result(Types.order())
  def create_order(credentials, order_params) do
    with {:ok, altname} <- Symbols.to_pair(order_params.symbol),
         body = Normalize.order_request(order_params, altname),
         {:ok, %{"txid" => [txid | _]}} <- post(credentials, "/0/private/AddOrder", body) do
      {:ok, Normalize.order_response_from_placement(order_params, txid)}
    end
  end

  @doc """
  Cancels an order. `POST /0/private/CancelOrder` -> Binance-shaped
  `%{"orderId" => _, "status" => "CANCELED", "symbol" => _}` when
  `result.count >= 1`. A `count` of `0` means no matching open order
  (already closed/filled, or an unknown txid) -- Kraken gives no further
  detail than the count.
  """
  @impl true
  @spec cancel_order(ExchangeClient.credentials(), Types.symbol(), Types.order_id()) ::
          Types.result(map())
  def cancel_order(credentials, symbol, order_id) do
    txid = to_string(order_id)

    with {:ok, %{"count" => count}} <- post(credentials, "/0/private/CancelOrder", %{txid: txid}) do
      if count >= 1 do
        {:ok, Normalize.cancel_response(txid, symbol)}
      else
        {:error,
         "Kraken CancelOrder: no matching open order (already closed, filled, or unknown txid)"}
      end
    end
  end

  @doc """
  Open orders, optionally filtered to one symbol. `POST
  /0/private/OpenOrders` returns `result.open`, a map keyed by txid (not a
  list). Kraken's `OpenOrders` has **no server-side symbol filter param**
  (unlike OKX's `instId` query param) -- when `symbol` is given, filtering
  happens client-side after each entry's `descr.pair` (an altname) is
  resolved to a concat symbol via `DataCollector.Kraken.Symbols.to_concat/1`.
  Entries whose `descr.pair` can't be resolved are logged and skipped.
  """
  @impl true
  @spec get_open_orders(ExchangeClient.credentials(), Types.symbol() | nil) ::
          Types.result([map()])
  def get_open_orders(credentials, symbol) do
    with {:ok, %{"open" => open}} <- post(credentials, "/0/private/OpenOrders", %{trades: false}) do
      orders =
        open
        |> Enum.flat_map(&resolve_open_order/1)
        |> filter_symbol(symbol)

      {:ok, orders}
    end
  end

  @doc """
  Public, unauthenticated. Built from
  `DataCollector.Kraken.Symbols.instrument_info/1` (no direct HTTP call
  here -- `Kraken.Symbols` owns the cached instrument fetch) into the
  Binance-shaped single-symbol `exchangeInfo` response
  `TradingEngine.SymbolInfo` parses.
  """
  @impl true
  @spec get_exchange_info(Types.symbol()) :: Types.result(map())
  def get_exchange_info(symbol) do
    with {:ok, info} <- Symbols.instrument_info(symbol) do
      {:ok, Normalize.exchange_info(info, symbol)}
    end
  end

  # -- private --

  defp resolve_open_order({txid, %{"descr" => %{"pair" => pair}} = entry}) do
    case Symbols.to_concat(pair) do
      {:ok, concat} ->
        [Normalize.open_order_response({txid, entry}, concat)]

      {:error, :unknown_symbol} ->
        Logger.warning(
          "DataCollector.KrakenClient: skipping open order for unknown pair " <> inspect(pair)
        )

        []
    end
  end

  defp resolve_open_order({txid, _entry}) do
    Logger.warning(
      "DataCollector.KrakenClient: skipping malformed OpenOrders entry for txid " <>
        inspect(txid)
    )

    []
  end

  # No server-side symbol filter exists on Kraken's OpenOrders endpoint --
  # filter client-side once every entry's concat symbol has been resolved.
  defp filter_symbol(orders, nil), do: orders
  defp filter_symbol(orders, symbol), do: Enum.filter(orders, &(&1["symbol"] == symbol))

  # Builds the nonce-included, form-urlencoded `postdata` string (used as
  # both the signed payload and the raw HTTP body -- see
  # `DataCollector.Kraken.Auth`), then delegates to `request/4`.
  defp post(credentials, urlpath, params) do
    postdata =
      params
      |> Map.put(:nonce, Auth.next_nonce())
      |> URI.encode_query()

    request("POST", urlpath, credentials, postdata)
  end

  defp request(method, urlpath, credentials, postdata) do
    headers = Auth.headers(credentials, urlpath, postdata)
    url = base_url() <> urlpath

    CircuitBreaker.call(:kraken_api, fn ->
      case http_call(method, url, postdata, headers) do
        {:ok, %{status_code: status, body: resp_body}} when status in 200..299 ->
          decode_envelope(resp_body)

        {:ok, %{status_code: status, body: resp_body}} ->
          {:error, "HTTP #{status}: #{resp_body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp http_call("POST", url, body, headers), do: HTTPoison.post(url, body, headers)

  # `%{"error" => [...], "result" => ...}` envelope (verified notes §2):
  # an empty `error` list means success; a non-empty one means failure and
  # `error`'s own `"E..."`/`"W..."` category-prefixed strings are passed
  # through as-is, joined, rather than reparsed.
  defp decode_envelope(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => [], "result" => result}} -> {:ok, result}
      {:ok, %{"error" => errors}} when is_list(errors) -> {:error, Enum.join(errors, "; ")}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:data_collector, :kraken, [])
    |> Keyword.get(:base_url, "https://api.kraken.com")
  end
end
