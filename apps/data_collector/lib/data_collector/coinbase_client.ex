defmodule DataCollector.CoinbaseClient do
  @moduledoc """
  HTTP client for the Coinbase Advanced Trade REST API, implementing
  `DataCollector.ExchangeClient`.

  Every private-endpoint payload this module returns (and accepts, for
  `create_order/2`) is normalized to/from Binance's exact key contracts via
  `DataCollector.Coinbase.Normalize`, the same "normalize everything into
  Binance's shape" strategy the OKX/Kraken adapters use. Symbol translation
  between Binance-style concat symbols (`"BTCUSD"`) and Coinbase
  `product_id`s (`"BTC-USD"`) goes through `DataCollector.Coinbase.Products`.

  Auth is a fresh ES256 JWT per request (`DataCollector.Coinbase.Auth.build_jwt/3`),
  sent as `Authorization: Bearer <jwt>` -- unlike Kraken's HMAC-SHA512 or
  OKX's HMAC-SHA256 prehash, there is no shared request-signing helper to
  build a raw body string from; the JWT's `uri` claim covers `method` +
  `path` only (no query string, matching the official SDK's
  `format_jwt_uri/2`).

  All calls go through `DataCollector.CircuitBreaker` under the
  `:coinbase_api` circuit, same pattern as `DataCollector.OKXClient`'s
  `:okx_api`/`DataCollector.KrakenClient`'s `:kraken_api`.
  """
  @behaviour DataCollector.ExchangeClient

  require Logger

  alias DataCollector.{CircuitBreaker, ExchangeClient}
  alias DataCollector.Coinbase.{Auth, Normalize, Products}
  alias SharedData.Types

  @doc """
  Account balances, paginated. Loops `GET /api/v3/brokerage/accounts` on
  `has_next`/`cursor`, accumulating `accounts` across every page, then
  hands the full flattened list to `Normalize.account_response/1`.
  """
  @impl true
  @spec get_account(ExchangeClient.credentials()) :: Types.result(map())
  def get_account(credentials) do
    with {:ok, accounts} <- fetch_all_accounts(credentials) do
      {:ok, Normalize.account_response(accounts)}
    end
  end

  @doc """
  Places an order. `order_params` is Binance-format (as built by the
  strategy layer). Places via `POST /api/v3/brokerage/orders`, which
  deliberately does not return price/qty/status (verified notes §2) --
  this is the one adapter of the three where a follow-up `GET
  /api/v3/brokerage/orders/historical/{order_id}` is unambiguously
  required (not optional, unlike OKX's/Kraken's own "GET after placing"
  posture) to build the full Binance-shaped reply.

  Coinbase's error response can arrive with **HTTP 200** -- the `success`
  boolean field is always checked explicitly, never inferred from the
  HTTP status code alone (verified notes §2).
  """
  @impl true
  @spec create_order(ExchangeClient.credentials(), Types.order_params()) ::
          Types.result(Types.order())
  def create_order(credentials, order_params) do
    with {:ok, product_id} <- Products.to_product_id(order_params.symbol),
         body = Normalize.order_request(order_params, product_id),
         {:ok, response} <- post(credentials, "/api/v3/brokerage/orders", body),
         {:ok, order_id} <- check_order_ack(response),
         {:ok, order} <- fetch_order(credentials, order_id) do
      {:ok, Normalize.order_response(order, order_params.symbol)}
    end
  end

  @doc """
  Cancels an order. `POST /api/v3/brokerage/orders/batch_cancel` with a
  single-element `order_ids` list -> `Normalize.cancel_response/2` on the
  single `results[]` entry (already returns a result tuple -- failure is
  a normal per-order outcome on this batch endpoint, passed straight
  through).
  """
  @impl true
  @spec cancel_order(ExchangeClient.credentials(), Types.symbol(), Types.order_id()) ::
          Types.result(map())
  def cancel_order(credentials, symbol, order_id) do
    body = %{order_ids: [to_string(order_id)]}

    with {:ok, %{"results" => [result | _]}} <-
           post(credentials, "/api/v3/brokerage/orders/batch_cancel", body) do
      Normalize.cancel_response(result, symbol)
    end
  end

  @doc """
  Open orders, optionally filtered to one symbol. `GET
  /api/v3/brokerage/orders/historical/batch?order_status=OPEN[&product_id=...]`
  -- the `product_id` filter is only added when `symbol` is non-nil,
  resolved via `Products.to_product_id/1`. Each `orders[]` entry already
  carries enough fields to normalize directly (verified notes §2's List
  Orders example) -- no additional per-order `GET` needed here, unlike
  `create_order/2`.
  """
  @impl true
  @spec get_open_orders(ExchangeClient.credentials(), Types.symbol() | nil) ::
          Types.result([map()])
  def get_open_orders(credentials, nil) do
    fetch_open_orders(credentials, %{})
  end

  def get_open_orders(credentials, symbol) do
    with {:ok, product_id} <- Products.to_product_id(symbol) do
      fetch_open_orders(credentials, %{product_id: product_id})
    end
  end

  @doc """
  Public, unauthenticated. Built from
  `DataCollector.Coinbase.Products.product_info/1` (no direct HTTP call
  here -- `Coinbase.Products` owns the cached product-list fetch) into
  the Binance-shaped single-symbol `exchangeInfo` response
  `TradingEngine.SymbolInfo` parses.
  """
  @impl true
  @spec get_exchange_info(Types.symbol()) :: Types.result(map())
  def get_exchange_info(symbol) do
    with {:ok, info} <- Products.product_info(symbol) do
      {:ok, Normalize.exchange_info(info, symbol)}
    end
  end

  # -- private --

  defp fetch_all_accounts(credentials), do: fetch_accounts_page(credentials, nil, [])

  defp fetch_accounts_page(credentials, cursor, acc) do
    query = maybe_put_cursor(%{}, cursor)

    with {:ok, %{"accounts" => accounts} = page} <-
           get(credentials, "/api/v3/brokerage/accounts", query) do
      acc = acc ++ accounts

      if page["has_next"] == true and is_binary(page["cursor"]) and page["cursor"] != "" do
        fetch_accounts_page(credentials, page["cursor"], acc)
      else
        {:ok, acc}
      end
    end
  end

  defp maybe_put_cursor(params, nil), do: params
  defp maybe_put_cursor(params, ""), do: params

  defp maybe_put_cursor(params, cursor) when is_binary(cursor),
    do: Map.put(params, :cursor, cursor)

  defp fetch_open_orders(credentials, extra_query) do
    query = Map.merge(%{order_status: "OPEN"}, extra_query)

    with {:ok, %{"orders" => orders}} <-
           get(credentials, "/api/v3/brokerage/orders/historical/batch", query) do
      resolved =
        Enum.flat_map(orders, fn order ->
          case Products.to_concat(order["product_id"]) do
            {:ok, concat} ->
              [Normalize.order_response(order, concat)]

            {:error, :unknown_symbol} ->
              Logger.warning(
                "DataCollector.CoinbaseClient: skipping open order for unknown product_id " <>
                  inspect(order["product_id"])
              )

              []
          end
        end)

      {:ok, resolved}
    end
  end

  defp fetch_order(credentials, order_id) do
    with {:ok, %{"order" => order}} <-
           get(credentials, "/api/v3/brokerage/orders/historical/#{order_id}") do
      {:ok, order}
    end
  end

  # The outer HTTP/envelope layer only tells us the request was
  # well-formed -- `create_order/2`'s actual accept/reject signal is the
  # `success` boolean inside the (always HTTP 200-or-2xx) body, checked
  # here explicitly (verified notes §2).
  defp check_order_ack(%{"success" => true, "success_response" => %{"order_id" => order_id}}) do
    {:ok, order_id}
  end

  defp check_order_ack(%{
         "success" => false,
         "error_response" => %{"new_order_failure_reason" => reason, "message" => msg}
       }) do
    {:error, "Coinbase order rejected (#{reason}): #{msg}"}
  end

  defp get(credentials, path), do: get(credentials, path, %{})
  defp get(credentials, path, query), do: request("GET", path, query, credentials, "")

  defp post(credentials, path, body_map),
    do: request("POST", path, %{}, credentials, Jason.encode!(body_map))

  defp build_path(path, query) when map_size(query) == 0, do: path
  defp build_path(path, query), do: path <> "?" <> URI.encode_query(query)

  defp request(method, path, query, credentials, body) do
    jwt = Auth.build_jwt(credentials, method, path)

    headers = [
      {"Authorization", "Bearer " <> jwt},
      {"Content-Type", "application/json"}
    ]

    url = base_url() <> build_path(path, query)

    CircuitBreaker.call(:coinbase_api, fn ->
      case http_call(method, url, body, headers) do
        {:ok, %{status_code: status, body: resp_body}} when status in 200..299 ->
          decode_envelope(resp_body)

        {:ok, %{status_code: status, body: resp_body}} ->
          {:error, "HTTP #{status}: #{resp_body}"}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp http_call("GET", url, _body, headers), do: HTTPoison.get(url, headers)
  defp http_call("POST", url, body, headers), do: HTTPoison.post(url, body, headers)

  # For non-order-specific failures (auth errors, malformed requests), the
  # generic `grpc.gateway.runtime.Error` envelope shape
  # (`%{"error", "code", "message"}`) is decoded to `{:error, message}`.
  # Order-specific `success: false` responses are NOT handled here --
  # those endpoints return HTTP 2xx with a `success` boolean, not a
  # `code`/`error` pair, and are checked explicitly in
  # `create_order/2`/`cancel_order/3` instead (verified notes §2).
  defp decode_envelope(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error, "code" => code, "message" => message}}
      when is_binary(error) and is_integer(code) ->
        {:error, message}

      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:data_collector, :coinbase, [])
    |> Keyword.get(:base_url, "https://api.coinbase.com")
  end
end
