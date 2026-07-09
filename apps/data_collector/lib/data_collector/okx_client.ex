defmodule DataCollector.OKXClient do
  @moduledoc """
  HTTP client for the OKX v5 REST API, implementing `DataCollector.ExchangeClient`.

  Every private-endpoint payload this module returns (and accepts, for
  `create_order/2`) is normalized to/from Binance's exact key contracts via
  `DataCollector.OKX.Normalize`, per the plan's "KEY ARCHITECTURAL DECISION"
  (see `docs/superpowers/plans/2026-07-09-okx-adapter.md` §1) — this lets
  the existing strategy/trading-engine layer consume OKX accounts with no
  changes. Symbol translation between Binance-style concat symbols
  (`"BTCUSDT"`) and OKX `instId`s (`"BTC-USDT"`) goes through
  `DataCollector.OKX.Symbols`.

  All calls go through `DataCollector.CircuitBreaker` under the `:okx_api`
  circuit, same pattern as `DataCollector.BinanceClient`'s `:binance_api`.
  """
  @behaviour DataCollector.ExchangeClient

  require Logger

  alias DataCollector.{CircuitBreaker, ExchangeClient}
  alias DataCollector.OKX.{Auth, Normalize, Symbols}
  alias SharedData.Types

  @doc """
  Account balances. `GET /api/v5/account/balance` -> Binance-shaped
  `%{"balances" => [%{"asset" => _, "free" => _, "locked" => _}], "accountType" => "SPOT"}`.
  """
  @impl true
  @spec get_account(ExchangeClient.credentials()) :: Types.result(map())
  def get_account(credentials) do
    with {:ok, %{"data" => data}} <- get(credentials, "/api/v5/account/balance") do
      {:ok, Normalize.account_response(data)}
    end
  end

  @doc """
  Places an order. `order_params` is Binance-format (as built by the
  strategy layer). Places via `POST /api/v5/trade/order`, then re-fetches
  the order via `GET /api/v5/trade/order` to build the full Binance-shaped
  reply (the placement response alone only carries `ordId`/`clOrdId`/`sCode`).
  """
  @impl true
  @spec create_order(ExchangeClient.credentials(), Types.order_params()) ::
          Types.result(Types.order())
  def create_order(credentials, order_params) do
    with {:ok, inst_id} <- Symbols.to_inst_id(order_params.symbol),
         body = Normalize.order_request(order_params, inst_id),
         {:ok, %{"data" => [placed | _]}} <- post(credentials, "/api/v5/trade/order", body),
         :ok <- check_order_ack(placed),
         {:ok, order} <- fetch_order(credentials, inst_id, placed["ordId"]) do
      {:ok, Normalize.order_response(order, order_params.symbol)}
    end
  end

  @doc """
  Cancels an order. `POST /api/v5/trade/cancel-order` -> Binance-shaped
  `%{"orderId" => _, "status" => "CANCELED", "symbol" => _}`.
  """
  @impl true
  @spec cancel_order(ExchangeClient.credentials(), Types.symbol(), Types.order_id()) ::
          Types.result(map())
  def cancel_order(credentials, symbol, order_id) do
    with {:ok, inst_id} <- Symbols.to_inst_id(symbol),
         body = %{instId: inst_id, ordId: to_string(order_id)},
         {:ok, %{"data" => [canceled | _]}} <-
           post(credentials, "/api/v5/trade/cancel-order", body),
         :ok <- check_order_ack(canceled) do
      {:ok, Normalize.cancel_response(canceled, symbol)}
    end
  end

  @doc """
  Open orders, optionally filtered to one symbol. `nil` returns every open
  SPOT order on the account. `GET /api/v5/trade/orders-pending` -> a list
  of Binance-shaped order maps.
  """
  @impl true
  @spec get_open_orders(ExchangeClient.credentials(), Types.symbol() | nil) ::
          Types.result([map()])
  def get_open_orders(credentials, nil) do
    fetch_open_orders(credentials, %{"instType" => "SPOT"})
  end

  def get_open_orders(credentials, symbol) do
    with {:ok, inst_id} <- Symbols.to_inst_id(symbol) do
      fetch_open_orders(credentials, %{"instType" => "SPOT", "instId" => inst_id})
    end
  end

  @doc """
  Public, unauthenticated. Built from `DataCollector.OKX.Symbols.instrument_info/1`
  (no direct HTTP call here — `OKX.Symbols` owns the cached instrument
  fetch) into the Binance-shaped single-symbol `exchangeInfo` response
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

  defp fetch_open_orders(credentials, query) do
    with {:ok, %{"data" => data}} <- get(credentials, "/api/v5/trade/orders-pending", query) do
      orders =
        Enum.flat_map(data, fn order ->
          case Symbols.to_concat(order["instId"]) do
            {:ok, concat} ->
              [Normalize.order_response(order, concat)]

            {:error, :unknown_symbol} ->
              Logger.warning(
                "DataCollector.OKXClient: skipping open order for unknown instId " <>
                  inspect(order["instId"])
              )

              []
          end
        end)

      {:ok, orders}
    end
  end

  defp fetch_order(credentials, inst_id, ord_id) do
    with {:ok, %{"data" => [order | _]}} <-
           get(credentials, "/api/v5/trade/order", %{"instId" => inst_id, "ordId" => ord_id}) do
      {:ok, order}
    end
  end

  # OKX order-placement/cancellation responses carry a per-order `sCode`
  # ("0" = accepted) inside `data[]` even when the outer envelope `code` is
  # "0" — the outer code only means "the request was well-formed", not
  # "the order itself succeeded" (e.g. insufficient balance still returns
  # outer code "0" with a non-"0" `sCode`/`sMsg` describing the rejection).
  defp check_order_ack(%{"sCode" => "0"}), do: :ok

  defp check_order_ack(%{"sCode" => code, "sMsg" => msg}),
    do: {:error, "OKX order rejected (#{code}): #{msg}"}

  defp check_order_ack(_other), do: :ok

  defp get(credentials, path), do: get(credentials, path, %{})

  defp get(credentials, path, query) do
    request_path = build_path(path, query)
    request("GET", request_path, credentials, "")
  end

  defp post(credentials, path, body_map) do
    request("POST", path, credentials, Jason.encode!(body_map))
  end

  defp build_path(path, query) when map_size(query) == 0, do: path
  defp build_path(path, query), do: path <> "?" <> URI.encode_query(query)

  defp request(method, request_path, credentials, body) do
    url = base_url() <> request_path
    headers = Auth.headers(credentials, method, request_path, body)

    CircuitBreaker.call(:okx_api, fn ->
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

  defp decode_envelope(body) do
    case Jason.decode(body) do
      {:ok, %{"code" => "0"} = envelope} -> {:ok, envelope}
      {:ok, %{"code" => code, "msg" => msg}} -> {:error, "OKX error #{code}: #{msg}"}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:data_collector, :okx, [])
    |> Keyword.get(:base_url, "https://www.okx.com")
  end
end
