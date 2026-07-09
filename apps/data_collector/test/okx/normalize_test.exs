defmodule DataCollector.OKX.NormalizeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias DataCollector.OKX.Normalize

  describe "order_status/1" do
    test "maps all documented OKX order states to Binance status strings" do
      assert Normalize.order_status("live") == "NEW"
      assert Normalize.order_status("partially_filled") == "PARTIALLY_FILLED"
      assert Normalize.order_status("filled") == "FILLED"
      assert Normalize.order_status("canceled") == "CANCELED"
      assert Normalize.order_status("mmp_canceled") == "CANCELED"
    end

    test "logs a warning and upcases unknown states instead of raising" do
      log =
        capture_log(fn ->
          assert Normalize.order_status("some_future_state") == "SOME_FUTURE_STATE"
        end)

      assert log =~ "unmapped OKX order state"
    end
  end

  describe "order_request/2" do
    test "builds a market BUY request with tgtCcy: base_ccy (Binance quantity semantics)" do
      params = %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: Decimal.new("0.001")}

      assert Normalize.order_request(params, "BTC-USDT") == %{
               instId: "BTC-USDT",
               tdMode: "cash",
               side: "buy",
               ordType: "market",
               sz: "0.001",
               tgtCcy: "base_ccy"
             }
    end

    test "builds a market SELL request without tgtCcy (already base-currency sz)" do
      params = %{symbol: "BTCUSDT", side: "SELL", type: "MARKET", quantity: Decimal.new("0.5")}

      result = Normalize.order_request(params, "BTC-USDT")

      assert result.side == "sell"
      assert result.ordType == "market"
      assert result.sz == "0.5"
      refute Map.has_key?(result, :tgtCcy)
    end

    test "builds a LIMIT request with px and without tgtCcy" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: Decimal.new("1"),
        price: Decimal.new("50000.5"),
        timeInForce: "GTC"
      }

      assert Normalize.order_request(params, "BTC-USDT") == %{
               instId: "BTC-USDT",
               tdMode: "cash",
               side: "buy",
               ordType: "limit",
               sz: "1",
               px: "50000.5"
             }
    end
  end

  describe "order_response/2" do
    # Modeled on the OKX canonical order-channel example reproduced in
    # docs/superpowers/notes/okx-api-verified.md §10 (same field names as
    # the REST GET /api/v5/trade/order response, per §4).
    @okx_order %{
      "accFillSz" => "1",
      "avgPx" => "50912.4",
      "clOrdId" => "testBTC0123",
      "instId" => "BTC-USDT",
      "ordId" => "288981657420439575",
      "ordType" => "limit",
      "px" => "50912.4",
      "side" => "buy",
      "state" => "filled",
      "sz" => "1"
    }

    test "maps to the exact Binance order-response key contract" do
      assert Normalize.order_response(@okx_order, "BTCUSDT") == %{
               "orderId" => "288981657420439575",
               "clientOrderId" => "testBTC0123",
               "symbol" => "BTCUSDT",
               "type" => "LIMIT",
               "side" => "BUY",
               "price" => "50912.4",
               "origQty" => "1",
               "executedQty" => "1",
               "status" => "FILLED",
               "timeInForce" => "GTC"
             }
    end

    test "upcases market order type/side and maps a live (NEW) state" do
      order = %{@okx_order | "ordType" => "market", "side" => "sell", "state" => "live"}

      result = Normalize.order_response(order, "BTCUSDT")

      assert result["type"] == "MARKET"
      assert result["side"] == "SELL"
      assert result["status"] == "NEW"
    end
  end

  describe "cancel_response/2" do
    test "builds the minimal Binance-shaped cancel confirmation" do
      assert Normalize.cancel_response(%{"ordId" => "12345", "clOrdId" => ""}, "BTCUSDT") == %{
               "orderId" => "12345",
               "status" => "CANCELED",
               "symbol" => "BTCUSDT"
             }
    end
  end

  describe "account_response/1" do
    # Modeled on GET /api/v5/account/balance data[0].details[] per verified
    # notes §4.
    test "maps details[] across accounts to Binance-shaped balances" do
      data = [
        %{
          "details" => [
            %{"ccy" => "BTC", "availBal" => "0.5", "frozenBal" => "0.1", "eq" => "0.6"},
            %{"ccy" => "USDT", "availBal" => "1000", "frozenBal" => "0", "eq" => "1000"}
          ]
        }
      ]

      assert Normalize.account_response(data) == %{
               "balances" => [
                 %{"asset" => "BTC", "free" => "0.5", "locked" => "0.1"},
                 %{"asset" => "USDT", "free" => "1000", "locked" => "0"}
               ],
               "accountType" => "SPOT"
             }
    end

    test "returns an empty balances list when data is empty" do
      assert Normalize.account_response([]) == %{"balances" => [], "accountType" => "SPOT"}
    end
  end

  describe "exchange_info/2" do
    test "builds a SymbolInfo-compatible single-symbol exchangeInfo map" do
      info = %{tick_sz: "0.1", lot_sz: "0.00000001", min_sz: "0.00001"}

      assert Normalize.exchange_info(info, "BTCUSDT") == %{
               "symbols" => [
                 %{
                   "symbol" => "BTCUSDT",
                   "filters" => [
                     %{"filterType" => "PRICE_FILTER", "tickSize" => "0.1"},
                     %{
                       "filterType" => "LOT_SIZE",
                       "stepSize" => "0.00000001",
                       "minQty" => "0.00001"
                     }
                   ]
                 }
               ]
             }
    end
  end
end
