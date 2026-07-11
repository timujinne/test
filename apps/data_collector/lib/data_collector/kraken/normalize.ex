defmodule DataCollector.Kraken.Normalize do
  @moduledoc """
  Pure functions that convert Kraken Spot REST and WebSocket v2 payloads
  into the exact Binance-shaped maps the strategy/trading-engine layer
  expects. Mirrors `DataCollector.OKX.Normalize`'s shape and role: every
  function here is side-effect-free (aside from a `Logger.warning/1` for
  unmapped statuses) so it can be unit-tested against canned fixtures with
  no HTTP/WS involved.

  ## REST vs WS status vocabularies are genuinely different

  Kraken's REST `OpenOrders` endpoint has **no distinct `PARTIALLY_FILLED`
  status** — a partially-filled order still reports `status: "open"`, and
  callers must derive `PARTIALLY_FILLED` themselves from `vol_exec > 0`
  (see `order_status/3`). The WS v2 `executions` channel, by contrast,
  *does* have a first-class `partially_filled` enum value (see
  `ws_order_status/1`). These are two separate mapping functions on
  purpose — don't collapse them into one.

  ## `volume` is always base-currency

  Unlike OKX (which needs `tgtCcy: "base_ccy"` on market BUY orders to get
  Binance `quantity` semantics), Kraken's `volume` field is
  base-currency-denominated by default for both market and limit orders,
  on both sides. This adapter never sets Kraken's `oflags: "viqc"` flag
  (which would switch `volume` to quote-currency for market buys) — so
  `order_request/2` never needs an OKX-style currency-target workaround.

  See `docs/superpowers/notes/kraken-api-verified.md` §2 and §4 for the
  REST/WS payload shapes these functions are modeled on.
  """

  require Logger

  alias DataCollector.Kraken.Symbols

  @doc """
  Maps a Kraken REST `OpenOrders` order to the Binance `status` string it
  represents (verified notes §2). There is no distinct `PARTIALLY_FILLED`
  value on this endpoint — an `"open"` order with `vol_exec > 0` is
  derived as `PARTIALLY_FILLED`; `"open"` with no executed volume is
  `NEW`. Unknown statuses are logged and passed through upcased rather
  than raising, same defensive convention as `OKX.Normalize.order_status/1`.
  """
  @spec order_status(String.t(), String.t(), String.t()) :: String.t()
  def order_status("pending", _vol, _vol_exec), do: "NEW"

  def order_status("open", _vol, vol_exec) do
    if Decimal.new(vol_exec) |> Decimal.gt?(Decimal.new(0)) do
      "PARTIALLY_FILLED"
    else
      "NEW"
    end
  end

  def order_status("closed", _vol, _vol_exec), do: "FILLED"
  def order_status("canceled", _vol, _vol_exec), do: "CANCELED"
  def order_status("expired", _vol, _vol_exec), do: "CANCELED"

  def order_status(other, _vol, _vol_exec) do
    Logger.warning(
      "DataCollector.Kraken.Normalize: unmapped Kraken order status #{inspect(other)}"
    )

    String.upcase(other)
  end

  @doc """
  Maps the WS v2 `executions` channel's own `order_status` enum
  (verified notes §4) to the Binance `status` string. Unlike
  `order_status/3`, this enum *does* have a first-class
  `"partially_filled"` value — deliberately a separate mapping function,
  see moduledoc.
  """
  @spec ws_order_status(String.t()) :: String.t()
  def ws_order_status("pending_new"), do: "NEW"
  def ws_order_status("new"), do: "NEW"
  def ws_order_status("partially_filled"), do: "PARTIALLY_FILLED"
  def ws_order_status("filled"), do: "FILLED"
  def ws_order_status("canceled"), do: "CANCELED"
  def ws_order_status("expired"), do: "CANCELED"

  def ws_order_status(other) do
    Logger.warning(
      "DataCollector.Kraken.Normalize: unmapped Kraken WS order_status #{inspect(other)}"
    )

    String.upcase(other)
  end

  @doc """
  Maps the WS v2 `executions` channel's own `exec_type` field to the
  Binance-shaped exec-type string. Unlike OKX (which has to derive this
  from `state`), Kraken sends a distinct field directly (verified notes
  §4). Values outside the 4-bucket Binance contract (`"amended"`,
  `"restated"`, `"status"`, `"iceberg_refill"`) are harmless/unused by
  current strategy code (which only reads `"NEW"`/`"TRADE"`/`"CANCELED"`)
  and pass through upcased.
  """
  @spec ws_exec_type(String.t()) :: String.t()
  def ws_exec_type("trade"), do: "TRADE"
  def ws_exec_type("new"), do: "NEW"
  def ws_exec_type("pending_new"), do: "NEW"
  def ws_exec_type("canceled"), do: "CANCELED"
  def ws_exec_type("expired"), do: "CANCELED"
  def ws_exec_type("filled"), do: "TRADE"
  def ws_exec_type(other), do: String.upcase(other)

  @doc """
  Binance-format `order_params` (as built by the strategy layer, e.g.
  `%{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: quantity}`)
  + the already-resolved Kraken `altname` for `order_params.symbol` (via
  `DataCollector.Kraken.Symbols.to_pair/1`) -> the `POST
  /0/private/AddOrder` request body map (`nonce` excluded here — added by
  `DataCollector.KrakenClient` right before signing/sending).

  `volume` is always base-currency-denominated (see moduledoc) — this
  never sets `oflags: "viqc"`. `cl_ord_id` is set (never `userref`, the
  two are mutually exclusive per verified notes §2) only when
  `order_params.client_order_id` is present and non-empty.
  """
  @spec order_request(map(), String.t()) :: map()
  def order_request(%{symbol: _symbol, side: side, type: type} = order_params, altname)
      when is_binary(altname) do
    %{
      pair: altname,
      type: String.downcase(side),
      ordertype: to_kraken_order_type(type),
      volume: to_string(order_params.quantity)
    }
    |> put_price(order_params)
    |> put_timeinforce(order_params)
    |> put_cl_ord_id(order_params)
  end

  defp to_kraken_order_type("MARKET"), do: "market"
  defp to_kraken_order_type("LIMIT"), do: "limit"
  defp to_kraken_order_type(other), do: String.downcase(other)

  defp put_price(body, %{price: price}) when not is_nil(price) do
    Map.put(body, :price, to_string(price))
  end

  defp put_price(body, _order_params), do: body

  defp put_timeinforce(body, order_params) do
    Map.put(body, :timeinforce, Map.get(order_params, :timeInForce) || "GTC")
  end

  defp put_cl_ord_id(body, order_params) do
    case Map.get(order_params, :client_order_id) do
      id when is_binary(id) and id != "" -> Map.put(body, :cl_ord_id, id)
      _other -> body
    end
  end

  @doc """
  Builds the Binance-shaped placement response **directly from the known
  request and the `AddOrder` ack's `txid`** — deliberately not a
  "GET the order right after placing" follow-up like OKX does. Kraken's
  `AddOrder` response only carries `descr`/`txid`, no price/qty/status
  detail, and the only REST follow-up (`OpenOrders`) won't contain the
  order at all if a market order filled instantly (closed/filled orders
  drop out of the open-orders set immediately — verified notes §2).
  Returns `"status" => "NEW"`/`"executedQty" => "0"` as the honest
  best-known state immediately after a synchronous placement call — the
  WS `executions` channel is the authoritative, fast-following source of
  truth for the real fill state from that point on, the same
  "REST placement ack is provisional, WS confirms" pattern the rest of the
  app already relies on for Binance/OKX.
  """
  @spec order_response_from_placement(map(), String.t()) :: map()
  def order_response_from_placement(order_params, txid) when is_binary(txid) do
    %{
      "orderId" => txid,
      "clientOrderId" => order_params[:client_order_id] || txid,
      "symbol" => order_params.symbol,
      "type" => String.upcase(order_params.type),
      "side" => String.upcase(order_params.side),
      "price" => order_params[:price] && to_string(order_params.price),
      "origQty" => to_string(order_params.quantity),
      "executedQty" => "0",
      "status" => "NEW",
      "timeInForce" => order_params[:timeInForce] || "GTC"
    }
  end

  @doc """
  A single `OpenOrders` `result.open` entry, given as `{txid, value}`
  (the txid is the map key in the raw response, not a field inside the
  value — see verified notes §2) + the already-resolved Binance-style
  concat symbol for the entry's `descr.pair` (via
  `DataCollector.Kraken.Symbols.to_concat/1`) -> the Binance-shaped order
  map. Kraken's `OpenOrders` entries don't echo back a client order id
  field in the documented shape, so `"clientOrderId"` falls back to the
  txid itself, matching the same "no better field available" fallback
  pattern used elsewhere.
  """
  @spec open_order_response({String.t(), map()}, String.t()) :: map()
  def open_order_response(
        {txid,
         %{
           "descr" => %{"ordertype" => ordertype, "type" => side, "price" => price},
           "vol" => vol,
           "vol_exec" => vol_exec,
           "status" => status
         }},
        concat_symbol
      )
      when is_binary(txid) and is_binary(concat_symbol) do
    %{
      "orderId" => txid,
      "clientOrderId" => txid,
      "symbol" => concat_symbol,
      "type" => String.upcase(ordertype),
      "side" => String.upcase(side),
      "price" => price,
      "origQty" => vol,
      "executedQty" => vol_exec,
      "status" => order_status(status, vol, vol_exec),
      "timeInForce" => "GTC"
    }
  end

  @doc """
  `(txid, concat_symbol)` -> the Binance-shaped cancel confirmation, given
  `POST /0/private/CancelOrder`'s `result.count >= 1` (no per-order status
  detail is available from this endpoint — verified notes §2).
  """
  @spec cancel_response(String.t(), String.t()) :: map()
  def cancel_response(txid, concat_symbol) when is_binary(txid) and is_binary(concat_symbol) do
    %{"orderId" => txid, "status" => "CANCELED", "symbol" => concat_symbol}
  end

  @doc """
  `POST /0/private/BalanceEx` `result` map
  (`%{asset_code => %{"balance" => num, "hold_trade" => num}}`) -> the
  Binance-shaped `%{"balances" => [%{"asset" => _, "free" => _, "locked" => _}]}`
  map. `asset` is translated via
  `DataCollector.Kraken.Symbols.asset_code_to_ticker/1`. `free = balance -
  hold_trade` (verified notes §2's own formula, simplified for a
  non-margin spot account) — both values arrive as JSON numbers, so they
  are wrapped with `Decimal.new(to_string(value))` before arithmetic.
  """
  @spec account_response(map()) :: map()
  def account_response(result) when is_map(result) do
    balances =
      Enum.map(result, fn {asset_code, %{"balance" => balance, "hold_trade" => hold_trade}} ->
        balance_dec = Decimal.new(to_string(balance))
        hold_dec = Decimal.new(to_string(hold_trade))
        free_dec = Decimal.sub(balance_dec, hold_dec)

        %{
          "asset" => Symbols.asset_code_to_ticker(asset_code),
          "free" => Decimal.to_string(free_dec),
          "locked" => Decimal.to_string(hold_dec)
        }
      end)

    %{"balances" => balances}
  end

  @doc """
  `DataCollector.Kraken.Symbols.instrument_info/1` result -> the
  Binance-shaped single-symbol `exchangeInfo` response
  `TradingEngine.SymbolInfo` parses (`PRICE_FILTER`/`tickSize`,
  `LOT_SIZE`/`stepSize`+`minQty`). Same shape as `OKX.Normalize.exchange_info/2`.
  """
  @spec exchange_info(map(), String.t()) :: map()
  def exchange_info(
        %{tick_size: tick_size, step_size: step_size, min_qty: min_qty},
        concat_symbol
      )
      when is_binary(concat_symbol) do
    %{
      "symbols" => [
        %{
          "symbol" => concat_symbol,
          "filters" => [
            %{"filterType" => "PRICE_FILTER", "tickSize" => tick_size},
            %{"filterType" => "LOT_SIZE", "stepSize" => step_size, "minQty" => min_qty}
          ]
        }
      ]
    }
  end

  @doc """
  A single WS v2 `ticker` channel data item + the already-resolved concat
  symbol -> the Binance-shaped `24hrTicker` map. Kraken's ticker push has
  no direct 24h-quote-volume field the way OKX's `volCcy24h` does, so
  `"q"` is left `nil` (no strategy code currently reads it off the ticker
  map; only `"s"`/`"c"` are load-bearing per the contract). `last`/`high`/
  `low`/`volume` arrive as JSON numbers, wrapped with `to_string/1` (not
  `Decimal`, since Binance's own ticker fields are plain strings and no
  arithmetic happens on this map downstream).
  """
  @spec ticker_event(map(), String.t()) :: map()
  def ticker_event(
        %{"last" => last, "high" => high, "low" => low, "volume" => volume},
        concat_symbol
      )
      when is_binary(concat_symbol) do
    %{
      "e" => "24hrTicker",
      "s" => concat_symbol,
      "c" => to_string(last),
      "o" => nil,
      "h" => to_string(high),
      "l" => to_string(low),
      "v" => to_string(volume),
      "q" => nil
    }
  end

  @doc """
  A single WS v2 `executions` channel data item + the already-resolved
  (already `/`-stripped) concat symbol -> the Binance-shaped
  `executionReport` map. Reads Kraken's WS field names (`order_id`,
  `side`, `order_status`, `exec_type`, `last_qty`, `last_price`,
  `cum_qty`, `order_qty` — verified notes §4's canonical example), which
  differ from the REST `OpenOrders` field names (e.g. `cum_qty` not
  `vol_exec`) — don't cross-wire the two. `last_qty`/`last_price` are only
  present on `exec_type: "trade"` pushes.
  """
  @spec execution_report(map(), String.t()) :: map()
  def execution_report(
        %{
          "order_id" => order_id,
          "side" => side,
          "order_status" => order_status,
          "exec_type" => exec_type,
          "cum_qty" => cum_qty,
          "order_qty" => order_qty
        } = item,
        concat_symbol
      )
      when is_binary(concat_symbol) do
    last_qty = Map.get(item, "last_qty")
    last_price = Map.get(item, "last_price")

    %{
      "e" => "executionReport",
      "i" => order_id,
      "s" => concat_symbol,
      "S" => String.upcase(side),
      "X" => ws_order_status(order_status),
      "x" => ws_exec_type(exec_type),
      "l" => last_qty && to_string(last_qty),
      "L" => last_price && to_string(last_price),
      "z" => to_string(cum_qty),
      "q" => to_string(order_qty)
    }
  end
end
