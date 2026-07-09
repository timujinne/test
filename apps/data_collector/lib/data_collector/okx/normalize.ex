defmodule DataCollector.OKX.Normalize do
  @moduledoc """
  Pure functions that convert OKX v5 REST (and, in Task 5, WS) payloads
  into the exact Binance-shaped maps the strategy/trading-engine layer
  expects.

  This is the load-bearing piece of the plan's "KEY ARCHITECTURAL DECISION"
  (`docs/superpowers/plans/2026-07-09-okx-adapter.md` §1): rather than
  refactor ~10 Binance-coupled strategy-layer modules, the OKX adapter
  normalizes every payload INTO Binance's key contracts. Every function
  here is side-effect-free (aside from a `Logger.warning/1` for unmapped
  order states) so it can be unit-tested against canned fixtures with no
  HTTP/WS involved.
  """

  require Logger

  @doc """
  Maps an OKX order `state` to the Binance `status` string it represents
  (see `docs/superpowers/notes/okx-api-verified.md` §7). Unknown states are
  logged and passed through upcased rather than raising, so an OKX API
  addition never crashes the adapter.
  """
  @spec order_status(String.t()) :: String.t()
  def order_status("live"), do: "NEW"
  def order_status("partially_filled"), do: "PARTIALLY_FILLED"
  def order_status("filled"), do: "FILLED"
  def order_status("canceled"), do: "CANCELED"
  # Market-Maker-Protection auto-cancel — documented as terminal alongside
  # "canceled" (verified notes §7); map it the same way.
  def order_status("mmp_canceled"), do: "CANCELED"

  def order_status(other) do
    Logger.warning("DataCollector.OKX.Normalize: unmapped OKX order state #{inspect(other)}")
    String.upcase(other)
  end

  @doc """
  Binance-format `order_params` (as built by the strategy layer, e.g.
  `%{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: quantity}`)
  -> the OKX `POST /api/v5/trade/order` request body map. `inst_id` is the
  already-resolved OKX instrument id for `order_params.symbol` (via
  `DataCollector.OKX.Symbols.to_inst_id/1`).

  Market BUY orders get `tgtCcy: "base_ccy"` so `sz` means "quantity of
  base currency to buy", matching Binance's `quantity` semantics (verified
  notes §5) — the default without `tgtCcy` would be quote-currency-denominated.
  Market SELL and all LIMIT orders are always base-currency `sz` on OKX, so
  no `tgtCcy` is needed for them.
  """
  @spec order_request(map(), String.t()) :: map()
  def order_request(%{symbol: _symbol, side: side, type: type} = order_params, inst_id)
      when is_binary(inst_id) do
    side_lower = String.downcase(side)
    ord_type = to_okx_order_type(type)

    %{instId: inst_id, tdMode: "cash", side: side_lower, ordType: ord_type}
    |> put_sz(order_params, ord_type, side_lower)
    |> put_px(order_params)
  end

  defp to_okx_order_type("MARKET"), do: "market"
  defp to_okx_order_type("LIMIT"), do: "limit"
  defp to_okx_order_type(other), do: String.downcase(other)

  defp put_sz(body, %{quantity: quantity}, "market", "buy") do
    body
    |> Map.put(:sz, to_string(quantity))
    |> Map.put(:tgtCcy, "base_ccy")
  end

  defp put_sz(body, %{quantity: quantity}, _ord_type, _side) do
    Map.put(body, :sz, to_string(quantity))
  end

  defp put_sz(body, _order_params, _ord_type, _side), do: body

  defp put_px(body, %{price: price}), do: Map.put(body, :px, to_string(price))
  defp put_px(body, _order_params), do: body

  @doc """
  A full OKX order object (as returned by `GET /api/v5/trade/order`, and —
  with the same field names — each entry of
  `GET /api/v5/trade/orders-pending`) -> the Binance-shaped order map the
  trading engine expects from `create_order/2` and `get_open_orders/2`.
  """
  @spec order_response(map(), String.t()) :: map()
  def order_response(
        %{
          "ordId" => ord_id,
          "clOrdId" => cl_ord_id,
          "ordType" => ord_type,
          "side" => side,
          "px" => px,
          "sz" => sz,
          "accFillSz" => acc_fill_sz,
          "state" => state
        },
        concat_symbol
      )
      when is_binary(concat_symbol) do
    %{
      "orderId" => ord_id,
      "clientOrderId" => cl_ord_id,
      "symbol" => concat_symbol,
      "type" => String.upcase(ord_type),
      "side" => String.upcase(side),
      "price" => px,
      "origQty" => sz,
      "executedQty" => acc_fill_sz,
      "status" => order_status(state),
      "timeInForce" => "GTC"
    }
  end

  @doc """
  `POST /api/v5/trade/cancel-order` response `data[0]` -> the smaller
  Binance-shaped cancel confirmation `TradingEngine.Trader` expects.
  """
  @spec cancel_response(map(), String.t()) :: map()
  def cancel_response(%{"ordId" => ord_id}, concat_symbol) when is_binary(concat_symbol) do
    %{"orderId" => ord_id, "status" => "CANCELED", "symbol" => concat_symbol}
  end

  @doc """
  `GET /api/v5/account/balance` response `data` list -> the Binance-shaped
  `%{"balances" => [...], "accountType" => "SPOT"}` map
  `DataCollector.BinanceClient.get_balances/2`-style callers expect.
  """
  @spec account_response([map()]) :: map()
  def account_response(data) when is_list(data) do
    balances =
      data
      |> Enum.flat_map(fn account -> Map.get(account, "details", []) end)
      |> Enum.map(fn %{"ccy" => ccy, "availBal" => avail_bal, "frozenBal" => frozen_bal} ->
        %{"asset" => ccy, "free" => avail_bal, "locked" => frozen_bal}
      end)

    %{"balances" => balances, "accountType" => "SPOT"}
  end

  @doc """
  `DataCollector.OKX.Symbols.instrument_info/1` result -> the Binance-shaped
  single-symbol `exchangeInfo` response `TradingEngine.SymbolInfo` parses
  (`PRICE_FILTER`/`tickSize`, `LOT_SIZE`/`stepSize`+`minQty`).
  """
  @spec exchange_info(map(), String.t()) :: map()
  def exchange_info(%{tick_sz: tick_sz, lot_sz: lot_sz, min_sz: min_sz}, concat_symbol)
      when is_binary(concat_symbol) do
    %{
      "symbols" => [
        %{
          "symbol" => concat_symbol,
          "filters" => [
            %{"filterType" => "PRICE_FILTER", "tickSize" => tick_sz},
            %{"filterType" => "LOT_SIZE", "stepSize" => lot_sz, "minQty" => min_sz}
          ]
        }
      ]
    }
  end
end
