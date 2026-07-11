defmodule DataCollector.Kraken.NormalizeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias DataCollector.Kraken.Normalize

  describe "order_status/3 (REST OpenOrders derivation)" do
    test "pending maps to NEW" do
      assert Normalize.order_status("pending", "1.0", "0") == "NEW"
    end

    test "open with vol_exec > 0 derives PARTIALLY_FILLED (no distinct REST status)" do
      assert Normalize.order_status("open", "1.25000000", "0.37500000") == "PARTIALLY_FILLED"
    end

    test "open with vol_exec == 0 maps to NEW" do
      assert Normalize.order_status("open", "1.25000000", "0.00000000") == "NEW"
    end

    test "closed maps to FILLED" do
      assert Normalize.order_status("closed", "1.0", "1.0") == "FILLED"
    end

    test "canceled maps to CANCELED" do
      assert Normalize.order_status("canceled", "1.0", "0") == "CANCELED"
    end

    test "expired maps to CANCELED" do
      assert Normalize.order_status("expired", "1.0", "0") == "CANCELED"
    end

    test "logs a warning and upcases unknown statuses instead of raising" do
      log =
        capture_log(fn ->
          assert Normalize.order_status("some_future_status", "1.0", "0") == "SOME_FUTURE_STATUS"
        end)

      assert log =~ "unmapped Kraken order status"
    end
  end

  describe "ws_order_status/1 (WS v2 executions channel enum)" do
    test "maps every documented WS status" do
      assert Normalize.ws_order_status("pending_new") == "NEW"
      assert Normalize.ws_order_status("new") == "NEW"
      assert Normalize.ws_order_status("partially_filled") == "PARTIALLY_FILLED"
      assert Normalize.ws_order_status("filled") == "FILLED"
      assert Normalize.ws_order_status("canceled") == "CANCELED"
      assert Normalize.ws_order_status("expired") == "CANCELED"
    end

    test "logs a warning and upcases unknown statuses instead of raising" do
      log =
        capture_log(fn ->
          assert Normalize.ws_order_status("some_future_status") == "SOME_FUTURE_STATUS"
        end)

      assert log =~ "unmapped Kraken WS order_status"
    end

    test "diverges from order_status/3: partially_filled only exists in the WS enum" do
      # REST OpenOrders has no "partially_filled" status value at all (it's
      # always "open" + vol_exec > 0 there) -- the WS enum has it as a
      # first-class value. Confirm the two mappings genuinely disagree on
      # this literal string.
      assert Normalize.ws_order_status("partially_filled") == "PARTIALLY_FILLED"

      log =
        capture_log(fn ->
          assert Normalize.order_status("partially_filled", "1.0", "0.5") == "PARTIALLY_FILLED"
        end)

      # order_status/3 has no clause for the literal string
      # "partially_filled" -- it falls through to the unknown-status
      # warning path (even though the resulting upcased string happens to
      # match), proving the two functions are genuinely different mappings
      # rather than aliases of each other.
      assert log =~ "unmapped Kraken order status"
    end
  end

  describe "ws_exec_type/1" do
    test "maps the core 4-bucket-relevant values" do
      assert Normalize.ws_exec_type("trade") == "TRADE"
      assert Normalize.ws_exec_type("new") == "NEW"
      assert Normalize.ws_exec_type("pending_new") == "NEW"
      assert Normalize.ws_exec_type("canceled") == "CANCELED"
      assert Normalize.ws_exec_type("expired") == "CANCELED"
      assert Normalize.ws_exec_type("filled") == "TRADE"
    end

    test "passes through non-4-bucket values upcased, no warning" do
      assert Normalize.ws_exec_type("amended") == "AMENDED"
      assert Normalize.ws_exec_type("restated") == "RESTATED"
      assert Normalize.ws_exec_type("status") == "STATUS"
      assert Normalize.ws_exec_type("iceberg_refill") == "ICEBERG_REFILL"
    end
  end

  describe "order_request/2" do
    test "builds a MARKET BUY request body: volume is base-currency, no viqc" do
      params = %{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: Decimal.new("0.001")}

      assert Normalize.order_request(params, "XBTUSD") == %{
               pair: "XBTUSD",
               type: "buy",
               ordertype: "market",
               volume: "0.001",
               timeinforce: "GTC"
             }
    end

    test "builds a LIMIT SELL request body with price and explicit timeInForce" do
      params = %{
        symbol: "BTCUSD",
        side: "SELL",
        type: "LIMIT",
        quantity: Decimal.new("1.25"),
        price: Decimal.new("37500"),
        timeInForce: "IOC"
      }

      assert Normalize.order_request(params, "XBTUSD") == %{
               pair: "XBTUSD",
               type: "sell",
               ordertype: "limit",
               volume: "1.25",
               price: "37500",
               timeinforce: "IOC"
             }
    end

    test "includes cl_ord_id only when client_order_id is present and non-empty" do
      params = %{
        symbol: "BTCUSD",
        side: "BUY",
        type: "MARKET",
        quantity: Decimal.new("1"),
        client_order_id: "arb-20240509-00010"
      }

      result = Normalize.order_request(params, "XBTUSD")
      assert result[:cl_ord_id] == "arb-20240509-00010"
      refute Map.has_key?(result, :userref)
    end

    test "omits cl_ord_id when client_order_id is empty or absent" do
      params = %{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: Decimal.new("1")}
      refute Map.has_key?(Normalize.order_request(params, "XBTUSD"), :cl_ord_id)

      params_empty = Map.put(params, :client_order_id, "")
      refute Map.has_key?(Normalize.order_request(params_empty, "XBTUSD"), :cl_ord_id)
    end
  end

  describe "order_response_from_placement/2" do
    test "builds a NEW + executedQty 0 response directly from the request and txid" do
      params = %{
        symbol: "BTCUSD",
        side: "BUY",
        type: "LIMIT",
        quantity: Decimal.new("1.45"),
        price: Decimal.new("27500")
      }

      assert Normalize.order_response_from_placement(params, "OU22CG-KLAF2-FWUDD7") == %{
               "orderId" => "OU22CG-KLAF2-FWUDD7",
               "clientOrderId" => "OU22CG-KLAF2-FWUDD7",
               "symbol" => "BTCUSD",
               "type" => "LIMIT",
               "side" => "BUY",
               "price" => "27500",
               "origQty" => "1.45",
               "executedQty" => "0",
               "status" => "NEW",
               "timeInForce" => "GTC"
             }
    end

    test "uses client_order_id as clientOrderId when present, nil price for MARKET orders" do
      params = %{
        symbol: "BTCUSD",
        side: "SELL",
        type: "MARKET",
        quantity: Decimal.new("0.5"),
        client_order_id: "my-client-id",
        timeInForce: "IOC"
      }

      result = Normalize.order_response_from_placement(params, "OABC12-XYZ89-DEF456")

      assert result["clientOrderId"] == "my-client-id"
      assert result["price"] == nil
      assert result["timeInForce"] == "IOC"
    end
  end

  describe "open_order_response/2" do
    # Kraken's own canonical OpenOrders example (verified notes §2).
    @open_entry {"OQCLML-BW3P3-BUCMWZ",
                 %{
                   "refid" => nil,
                   "userref" => 0,
                   "status" => "open",
                   "opentm" => 1_688_666_559.8974,
                   "starttm" => 0,
                   "expiretm" => 0,
                   "descr" => %{
                     "pair" => "XBTUSD",
                     "type" => "buy",
                     "ordertype" => "limit",
                     "price" => "30010.0"
                   },
                   "vol" => "1.25000000",
                   "vol_exec" => "0.37500000",
                   "cost" => "11253.7",
                   "fee" => "0.00000",
                   "price" => "30010.0",
                   "misc" => "",
                   "oflags" => "fciq",
                   "trades" => ["TCCCTY-WE2O6-P3NB37"]
                 }}

    test "maps to the Binance order key contract, deriving PARTIALLY_FILLED" do
      assert Normalize.open_order_response(@open_entry, "BTCUSD") == %{
               "orderId" => "OQCLML-BW3P3-BUCMWZ",
               "clientOrderId" => "OQCLML-BW3P3-BUCMWZ",
               "symbol" => "BTCUSD",
               "type" => "LIMIT",
               "side" => "BUY",
               "price" => "30010.0",
               "origQty" => "1.25000000",
               "executedQty" => "0.37500000",
               "status" => "PARTIALLY_FILLED",
               "timeInForce" => "GTC"
             }
    end

    test "maps a fresh unexecuted open order to NEW" do
      {txid, entry} = @open_entry
      entry = %{entry | "vol_exec" => "0.00000000"}

      result = Normalize.open_order_response({txid, entry}, "BTCUSD")
      assert result["status"] == "NEW"
    end
  end

  describe "cancel_response/2" do
    test "builds the minimal Binance-shaped cancel confirmation" do
      assert Normalize.cancel_response("OHYO67-6LP66-HMQ437", "BTCUSD") == %{
               "orderId" => "OHYO67-6LP66-HMQ437",
               "status" => "CANCELED",
               "symbol" => "BTCUSD"
             }
    end
  end

  describe "account_response/1" do
    test "computes free = balance - hold_trade on the verified notes' own worked numbers" do
      result =
        Normalize.account_response(%{
          "ZUSD" => %{"balance" => 25_435.21, "hold_trade" => 8249.76}
        })

      assert result == %{
               "balances" => [
                 %{"asset" => "USD", "free" => "17185.45", "locked" => "8249.76"}
               ]
             }
    end

    test "translates asset codes via Kraken.Symbols.asset_code_to_ticker/1" do
      result =
        Normalize.account_response(%{
          "XXBT" => %{"balance" => 1.2435, "hold_trade" => 0.8423},
          "USDT" => %{"balance" => 500_000.0, "hold_trade" => 0.0}
        })

      balances = Map.new(result["balances"], &{&1["asset"], &1})

      assert balances["BTC"]["free"] == "0.4012"
      assert balances["BTC"]["locked"] == "0.8423"
      assert balances["USDT"]["free"] == "500000.0"
      assert balances["USDT"]["locked"] == "0.0"
    end

    test "returns an empty balances list for an empty result map" do
      assert Normalize.account_response(%{}) == %{"balances" => []}
    end
  end

  describe "exchange_info/2" do
    test "builds a SymbolInfo-compatible single-symbol exchangeInfo map" do
      info = %{tick_size: "0.1", step_size: "0.00000001", min_qty: "0.00005"}

      assert Normalize.exchange_info(info, "BTCUSD") == %{
               "symbols" => [
                 %{
                   "symbol" => "BTCUSD",
                   "filters" => [
                     %{"filterType" => "PRICE_FILTER", "tickSize" => "0.1"},
                     %{
                       "filterType" => "LOT_SIZE",
                       "stepSize" => "0.00000001",
                       "minQty" => "0.00005"
                     }
                   ]
                 }
               ]
             }
    end
  end

  describe "ticker_event/2" do
    # Kraken's own canonical WS v2 ticker channel push example (verified
    # notes §4), symbol-adapted.
    @kraken_ticker %{
      "symbol" => "BTC/USD",
      "bid" => 0.10025,
      "bid_qty" => 740.0,
      "ask" => 0.10036,
      "ask_qty" => 1361.44813783,
      "last" => 0.10035,
      "volume" => 997_038.98383185,
      "vwap" => 0.10148,
      "low" => 0.09979,
      "high" => 0.10285,
      "change" => -0.00017,
      "change_pct" => -0.17,
      "timestamp" => "2023-09-25T09:04:31.742648Z"
    }

    test "maps to the Binance 24hrTicker key contract, q and o left nil" do
      assert Normalize.ticker_event(@kraken_ticker, "BTCUSD") == %{
               "e" => "24hrTicker",
               "s" => "BTCUSD",
               "c" => "0.10035",
               "o" => nil,
               "h" => "0.10285",
               "l" => "0.09979",
               "v" => "997038.98383185",
               "q" => nil
             }
    end
  end

  describe "execution_report/2" do
    # Kraken's own canonical WS v2 executions channel push example
    # (verified notes §4).
    @kraken_execution %{
      "order_id" => "OK4GJX-KSTLS-7DZZO5",
      "order_userref" => 3,
      "exec_id" => "TGBB7L-HT5LX-J3BZ4A",
      "exec_type" => "trade",
      "trade_id" => 62_887_576,
      "symbol" => "BTC/USD",
      "side" => "sell",
      "last_qty" => 0.005,
      "last_price" => 26_599.9,
      "liquidity_ind" => "t",
      "cost" => 132.9995,
      "order_type" => "limit",
      "timestamp" => "2023-09-22T10:33:05.709993Z",
      "order_status" => "partially_filled",
      "cum_qty" => 0.005,
      "cum_cost" => 132.9995,
      "avg_price" => 26_599.9,
      "order_qty" => 0.005,
      "fee_usd_equiv" => 0.3458,
      "fees" => [%{"asset" => "USD", "qty" => 0.3458}]
    }

    test "maps a trade push to the Binance executionReport key contract" do
      assert Normalize.execution_report(@kraken_execution, "BTCUSD") == %{
               "e" => "executionReport",
               "i" => "OK4GJX-KSTLS-7DZZO5",
               "s" => "BTCUSD",
               "S" => "SELL",
               "X" => "PARTIALLY_FILLED",
               "x" => "TRADE",
               "l" => "0.005",
               "L" => "26599.9",
               "z" => "0.005",
               "q" => "0.005"
             }
    end

    test "omits last_qty/last_price (nil) when absent, e.g. a non-trade new push" do
      push =
        @kraken_execution
        |> Map.delete("last_qty")
        |> Map.delete("last_price")
        |> Map.put("exec_type", "new")
        |> Map.put("order_status", "new")
        |> Map.put("cum_qty", 0)

      result = Normalize.execution_report(push, "BTCUSD")

      assert result["l"] == nil
      assert result["L"] == nil
      assert result["X"] == "NEW"
      assert result["x"] == "NEW"
      assert result["z"] == "0"
    end
  end
end
