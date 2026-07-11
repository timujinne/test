defmodule DataCollector.Coinbase.Normalize do
  @moduledoc """
  Pure functions that convert Coinbase Advanced Trade REST and WebSocket
  payloads into the exact Binance-shaped maps the strategy/trading-engine
  layer expects. Mirrors `DataCollector.OKX.Normalize`/`DataCollector.Kraken.Normalize`'s
  shape and role: every function here is side-effect-free (aside from a
  `Logger.warning/1` for unmapped statuses) so it can be unit-tested
  against canned fixtures with no HTTP/WS involved.

  ## `base_size` is unconditionally base-currency

  Unlike OKX (which needs `tgtCcy: "base_ccy"` on market BUY orders) or
  Kraken (which must avoid ever setting `oflags: "viqc"`), Coinbase's
  `order_configuration` always uses `base_size` (never `quote_size`) for
  every order this app places — matching Binance's `quantity` semantics
  with no analog to either other adapter's currency-target gotcha. This is
  the simplest of the three adapters on this exact point.

  ## No distinct `PARTIALLY_FILLED` status (REST or WS)

  Same "REST-shows-fewer-buckets" pattern the Kraken scout found on
  `OpenOrders`: Coinbase's `status` enum (identical values on both REST
  and the WS `user` channel — see verified notes §2.5/§4) has no
  first-class `PARTIALLY_FILLED` value. A partially-filled order is still
  `status: "OPEN"`, just with `0 < filled size < order size` — derived in
  `order_status/3`, reused for both the REST and WS paths (unlike Kraken,
  which needs two separate mapping functions because its WS enum *does*
  have a distinct `partially_filled` value).

  ## The WS `user` channel is a genuinely thinner payload

  Coinbase's `user` channel order events don't send a per-fill delta size,
  a last-fill price, or the original order size directly (verified notes
  §4) — only cumulative figures (`cumulative_quantity`) and a leaves
  (remaining) quantity. `execution_report/3` derives `"l"` (last fill
  qty) as a `cumulative_quantity` delta against a caller-supplied
  `prev_cum_qty` (tracked per-order by `DataCollector.CoinbasePrivateStream`,
  reset to zero on every reconnect — an accepted, documented limitation,
  not a bug), derives `"q"` (orig qty) as `cumulative_quantity +
  leaves_quantity`, and reports `"L"` (last fill price) as
  `avg_price` — a cumulative *average* price, **not** a true last-fill
  price (Coinbase sends no such field on this channel). This is flagged
  explicitly here, not a silent approximation.

  See `docs/superpowers/notes/coinbase-api-verified.md` §2 and §4 for the
  REST/WS payload shapes these functions are modeled on.
  """

  require Logger

  @doc """
  Maps a Coinbase `status` (identical enum on REST `Get Order`/`List
  Orders` and the WS `user` channel's own `status` field — verified notes
  §2.5/§4) to the Binance `status` string it represents. There is no
  distinct `PARTIALLY_FILLED` value in this enum — an `"OPEN"` order with
  `0 < filled_size < order_size` is derived as `PARTIALLY_FILLED`;
  `"OPEN"` otherwise is `NEW`. Unknown statuses are logged and passed
  through upcased rather than raising, same defensive convention as
  `OKX.Normalize.order_status/1`/`Kraken.Normalize.order_status/3`.
  """
  @spec order_status(String.t(), String.t(), String.t()) :: String.t()
  def order_status(status, _filled_size, _order_size)
      when status in ["PENDING", "QUEUED", "CANCEL_QUEUED", "EDIT_QUEUED"],
      do: "NEW"

  def order_status("OPEN", filled_size, order_size) do
    filled_dec = Decimal.new(filled_size)

    if Decimal.gt?(filled_dec, Decimal.new(0)) and
         Decimal.lt?(filled_dec, Decimal.new(order_size)) do
      "PARTIALLY_FILLED"
    else
      "NEW"
    end
  end

  def order_status("FILLED", _filled_size, _order_size), do: "FILLED"
  # Coinbase's own spelling is double-L ("CANCELLED", British) — pattern-
  # matched here exactly as the raw field value arrives. Only the app's
  # own normalized output uses the single-L American "CANCELED".
  def order_status("CANCELLED", _filled_size, _order_size), do: "CANCELED"
  def order_status("EXPIRED", _filled_size, _order_size), do: "CANCELED"
  def order_status("FAILED", _filled_size, _order_size), do: "CANCELED"

  def order_status(other, _filled_size, _order_size) do
    Logger.warning(
      "DataCollector.Coinbase.Normalize: unmapped Coinbase order status #{inspect(other)}"
    )

    String.upcase(other)
  end

  @doc """
  Binance-format `order_params` (as built by the strategy layer, e.g.
  `%{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: quantity}`)
  -> the Coinbase `order_configuration` body fragment (verified notes §2).
  Always uses `base_size` (see moduledoc) -- never `quote_size`.
  """
  @spec order_configuration(map()) :: map()
  def order_configuration(%{type: "MARKET", quantity: quantity}) do
    %{market_market_ioc: %{base_size: to_string(quantity)}}
  end

  def order_configuration(%{type: "LIMIT", quantity: quantity, price: price}) do
    %{
      limit_limit_gtc: %{
        base_size: to_string(quantity),
        limit_price: to_string(price),
        post_only: false
      }
    }
  end

  @doc """
  Binance-format `order_params` + the already-resolved Coinbase
  `product_id` for `order_params.symbol` (via
  `DataCollector.Coinbase.Products.to_product_id/1`) -> the `POST
  /api/v3/brokerage/orders` request body map.

  `client_order_id` always sends our own id (never an empty string) via
  `generate_client_order_id/0` when `order_params` doesn't already carry
  one -- an empty string auto-generates one server-side but forfeits the
  duplicate-order safeguard (verified notes §2), so this adapter always
  sends its own so retries/reconciliation can use it.
  """
  @spec order_request(map(), String.t()) :: map()
  def order_request(%{symbol: _symbol, side: side} = order_params, product_id)
      when is_binary(product_id) do
    %{
      client_order_id: order_params[:client_order_id] || generate_client_order_id(),
      product_id: product_id,
      side: String.upcase(side),
      order_configuration: order_configuration(order_params)
    }
  end

  defp generate_client_order_id, do: Ecto.UUID.generate()

  @doc """
  A Coinbase `GET /api/v3/brokerage/orders/historical/{order_id}` order
  object (already unwrapped from its `"order"` envelope key by
  `DataCollector.CoinbaseClient`; the same flat shape also matches each
  entry of `GET /api/v3/brokerage/orders/historical/batch`'s `orders[]`
  list, verified notes §2) + the already-resolved Binance-style concat
  symbol for the order's `product_id` -> the Binance-shaped order map.

  `"price"` prefers the echoed `order_configuration`'s `limit_limit_gtc.limit_price`
  for limit orders; for market orders (no `limit_price` in the echoed
  config) it falls back to `average_filled_price`, which may be `nil`/`"0"`
  pre-fill -- passed through as-is, matching how downstream code already
  tolerates a nil/zero price for unfilled OKX/Kraken orders. `"origQty"`
  reads whichever of `base_size`/`quote_size` is actually present in the
  echoed `order_configuration`. `"timeInForce"` is hardcoded `"GTC"` --
  this app never places `market_market_ioc` with a different TIF
  semantic worth surfacing, matching the OKX/Kraken adapters' own
  hardcoded `"GTC"` fallback.
  """
  @spec order_response(map(), String.t()) :: map()
  def order_response(
        %{
          "order_id" => order_id,
          "client_order_id" => client_order_id,
          "order_type" => order_type,
          "side" => side,
          "filled_size" => filled_size,
          "average_filled_price" => average_filled_price,
          "order_configuration" => order_configuration,
          "status" => status
        },
        concat_symbol
      )
      when is_binary(concat_symbol) do
    {orig_qty, limit_price} = extract_order_configuration(order_configuration)
    price = limit_price || average_filled_price

    %{
      "orderId" => order_id,
      "clientOrderId" => client_order_id,
      "symbol" => concat_symbol,
      "type" => String.upcase(order_type),
      "side" => String.upcase(side),
      "price" => price,
      "origQty" => orig_qty,
      "executedQty" => filled_size,
      "status" => order_status(status, filled_size, orig_qty),
      "timeInForce" => "GTC"
    }
  end

  defp extract_order_configuration(%{"limit_limit_gtc" => %{"limit_price" => limit_price} = cfg}) do
    {order_size_from_config(cfg), limit_price}
  end

  defp extract_order_configuration(%{"market_market_ioc" => cfg}) do
    {order_size_from_config(cfg), nil}
  end

  defp order_size_from_config(%{"base_size" => base_size}), do: base_size
  defp order_size_from_config(%{"quote_size" => quote_size}), do: quote_size

  @doc """
  A single `POST /api/v3/brokerage/orders/batch_cancel` `results[]` entry
  + the already-resolved concat symbol -> a result tuple (not a bare map
  -- failure is a normal per-order outcome on this batch endpoint, the
  caller in `DataCollector.CoinbaseClient.cancel_order/3` unwraps it):
  `{:ok, binance_shaped_map}` when `success == true`, `{:error,
  failure_reason}` when `success == false`.
  """
  @spec cancel_response(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def cancel_response(%{"success" => true, "order_id" => order_id}, concat_symbol)
      when is_binary(concat_symbol) do
    {:ok, %{"orderId" => order_id, "status" => "CANCELED", "symbol" => concat_symbol}}
  end

  def cancel_response(%{"success" => false, "failure_reason" => failure_reason}, concat_symbol)
      when is_binary(concat_symbol) do
    {:error, failure_reason}
  end

  @doc """
  A flattened, already-fully-paginated `accounts` list (pagination itself
  is `DataCollector.CoinbaseClient`'s job -- this function receives the
  full accumulated list) -> the Binance-shaped `%{"balances" =>
  [%{"asset", "free", "locked"}]}` map, reading each entry's `currency`,
  `available_balance.value`, `hold.value` (verified notes §2's
  live-confirmed sandbox example).
  """
  @spec account_response([map()]) :: map()
  def account_response(accounts) when is_list(accounts) do
    balances =
      Enum.map(accounts, fn %{
                              "currency" => currency,
                              "available_balance" => %{"value" => free},
                              "hold" => %{"value" => locked}
                            } ->
        %{"asset" => currency, "free" => free, "locked" => locked}
      end)

    %{"balances" => balances}
  end

  @doc """
  `DataCollector.Coinbase.Products.product_info/1` result -> the
  Binance-shaped single-symbol `exchangeInfo` response
  `TradingEngine.SymbolInfo` parses (`PRICE_FILTER`/`tickSize`,
  `LOT_SIZE`/`stepSize`+`minQty`). Same shape as
  `OKX.Normalize.exchange_info/2`/`Kraken.Normalize.exchange_info/2`.
  """
  @spec exchange_info(map(), String.t()) :: map()
  def exchange_info(
        %{
          base_increment: base_increment,
          quote_increment: quote_increment,
          base_min_size: base_min_size
        },
        concat_symbol
      )
      when is_binary(concat_symbol) do
    %{
      "symbols" => [
        %{
          "symbol" => concat_symbol,
          "filters" => [
            %{"filterType" => "PRICE_FILTER", "tickSize" => quote_increment},
            %{"filterType" => "LOT_SIZE", "stepSize" => base_increment, "minQty" => base_min_size}
          ]
        }
      ]
    }
  end

  @doc """
  A single WS `ticker` channel `events[].tickers[]` item + the
  already-resolved concat symbol -> the Binance-shaped `24hrTicker` map.
  Coinbase's own field names (`price`, `high_24_h`, `low_24_h`,
  `volume_24_h`) are already strings in the WS payload (verified notes
  §4) -- no `to_string` wrapping needed, unlike Kraken's numeric WS
  ticker fields. `"q"` is left `nil`, same "no direct 24h-quote-volume
  field" reasoning as Kraken's ticker_event/2.
  """
  @spec ticker_event(map(), String.t()) :: map()
  def ticker_event(
        %{
          "price" => price,
          "high_24_h" => high_24_h,
          "low_24_h" => low_24_h,
          "volume_24_h" => volume_24_h
        },
        concat_symbol
      )
      when is_binary(concat_symbol) do
    %{
      "e" => "24hrTicker",
      "s" => concat_symbol,
      "c" => price,
      "o" => nil,
      "h" => high_24_h,
      "l" => low_24_h,
      "v" => volume_24_h,
      "q" => nil
    }
  end

  @doc """
  A single WS `user` channel `events[].orders[]` item + the
  already-resolved concat symbol + the previously-seen cumulative fill
  quantity for this order (`prev_cum_qty`, tracked by
  `DataCollector.CoinbasePrivateStream`, seeded to `Decimal.new(0)` the
  first time an order_id is seen -- including right after any reconnect,
  see moduledoc) -> the Binance-shaped `executionReport` map.

  Reads `order_side` (**not** `side` -- the WS `user` channel names this
  field differently from every REST endpoint, verified notes §4, an easy
  cross-wiring trap if this normalizer were copy-pasted from the
  REST-order-mapping code path). `"l"` is derived as the
  `cumulative_quantity` delta against `prev_cum_qty`; `"q"` is derived as
  `cumulative_quantity + leaves_quantity`; `"L"` is `avg_price`, a
  cumulative-average price, **not** a true last-fill price -- Coinbase
  sends no such field on this channel, flagged explicitly (see
  moduledoc), not a silent guess.
  """
  @spec execution_report(map(), String.t(), Decimal.t()) :: map()
  def execution_report(
        %{
          "order_id" => order_id,
          "order_side" => order_side,
          "status" => status,
          "cumulative_quantity" => cumulative_quantity,
          "leaves_quantity" => leaves_quantity,
          "avg_price" => avg_price
        },
        concat_symbol,
        %Decimal{} = prev_cum_qty
      )
      when is_binary(concat_symbol) do
    cum_qty = Decimal.new(cumulative_quantity)
    last_qty = Decimal.sub(cum_qty, prev_cum_qty)
    leaves_qty = Decimal.new(leaves_quantity)
    order_qty = Decimal.add(cum_qty, leaves_qty)

    %{
      "e" => "executionReport",
      "i" => order_id,
      "s" => concat_symbol,
      "S" => String.upcase(order_side),
      "X" => order_status(status, cumulative_quantity, Decimal.to_string(order_qty)),
      "x" => ws_exec_type(status, last_qty),
      "l" => Decimal.to_string(last_qty),
      "L" => avg_price,
      "z" => cumulative_quantity,
      "q" => Decimal.to_string(order_qty)
    }
  end

  # Derives the Binance-style exec-type (`"NEW"`/`"TRADE"`/`"CANCELED"`)
  # from a Coinbase WS `user`-channel order `status` + the just-derived
  # `last_qty` delta, since Coinbase doesn't push a separate exec-type
  # field either (same derivation burden as OKX/verified notes §4).
  defp ws_exec_type("FILLED", _last_qty), do: "TRADE"

  defp ws_exec_type("OPEN", last_qty) do
    if Decimal.gt?(last_qty, Decimal.new(0)) do
      "TRADE"
    else
      "NEW"
    end
  end

  defp ws_exec_type(status, _last_qty) when status in ["CANCELLED", "EXPIRED", "FAILED"],
    do: "CANCELED"

  defp ws_exec_type(status, _last_qty), do: String.upcase(status)
end
