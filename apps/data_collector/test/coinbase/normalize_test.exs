defmodule DataCollector.Coinbase.NormalizeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias DataCollector.Coinbase.Normalize

  describe "order_status/3" do
    test "PENDING/QUEUED/CANCEL_QUEUED/EDIT_QUEUED all map to NEW regardless of fill" do
      assert Normalize.order_status("PENDING", "0", "1.0") == "NEW"
      assert Normalize.order_status("QUEUED", "0", "1.0") == "NEW"
      assert Normalize.order_status("CANCEL_QUEUED", "0.2", "1.0") == "NEW"
      assert Normalize.order_status("EDIT_QUEUED", "0.2", "1.0") == "NEW"
    end

    test "OPEN with 0 < filled < order size derives PARTIALLY_FILLED (no distinct REST/WS status)" do
      assert Normalize.order_status("OPEN", "0.01", "0.05") == "PARTIALLY_FILLED"
    end

    test "OPEN with filled == 0 maps to NEW" do
      assert Normalize.order_status("OPEN", "0", "0.05") == "NEW"
    end

    test "OPEN with filled == order size (boundary) maps to NEW, not PARTIALLY_FILLED" do
      assert Normalize.order_status("OPEN", "0.05", "0.05") == "NEW"
    end

    test "FILLED maps to FILLED" do
      assert Normalize.order_status("FILLED", "1.0", "1.0") == "FILLED"
    end

    test "CANCELLED (double-L, Coinbase's own spelling) maps to CANCELED (single-L)" do
      assert Normalize.order_status("CANCELLED", "0.5", "1.0") == "CANCELED"
    end

    test "EXPIRED maps to CANCELED" do
      assert Normalize.order_status("EXPIRED", "0", "1.0") == "CANCELED"
    end

    test "FAILED maps to CANCELED" do
      assert Normalize.order_status("FAILED", "0", "1.0") == "CANCELED"
    end

    test "logs a warning and upcases unknown statuses instead of raising" do
      log =
        capture_log(fn ->
          assert Normalize.order_status("UNKNOWN_ORDER_STATUS", "0", "1.0") ==
                   "UNKNOWN_ORDER_STATUS"
        end)

      assert log =~ "unmapped Coinbase order status"
    end
  end

  describe "order_configuration/1" do
    test "MARKET always uses base_size" do
      params = %{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: Decimal.new("0.05")}

      assert Normalize.order_configuration(params) == %{
               market_market_ioc: %{base_size: "0.05"}
             }
    end

    test "LIMIT uses base_size + limit_price + post_only: false" do
      params = %{
        symbol: "BTCUSD",
        side: "SELL",
        type: "LIMIT",
        quantity: Decimal.new("0.001"),
        price: Decimal.new("10000.00")
      }

      assert Normalize.order_configuration(params) == %{
               limit_limit_gtc: %{
                 base_size: "0.001",
                 limit_price: "10000.00",
                 post_only: false
               }
             }
    end
  end

  describe "order_request/2" do
    test "builds the POST /orders body, using the given client_order_id when present" do
      params = %{
        symbol: "BTCUSD",
        side: "BUY",
        type: "LIMIT",
        quantity: Decimal.new("0.001"),
        price: Decimal.new("10000.00"),
        client_order_id: "0000-00000-000000"
      }

      assert Normalize.order_request(params, "BTC-USD") == %{
               client_order_id: "0000-00000-000000",
               product_id: "BTC-USD",
               side: "BUY",
               order_configuration: %{
                 limit_limit_gtc: %{
                   base_size: "0.001",
                   limit_price: "10000.00",
                   post_only: false
                 }
               }
             }
    end

    test "generates a non-empty client_order_id when absent (never empty, per verified notes §2)" do
      params = %{symbol: "BTCUSD", side: "BUY", type: "MARKET", quantity: Decimal.new("0.05")}

      result = Normalize.order_request(params, "BTC-USD")

      assert is_binary(result.client_order_id)
      assert result.client_order_id != ""
      # Ecto.UUID.generate/0 shape.
      assert result.client_order_id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end

    test "generates a different client_order_id on each call" do
      params = %{symbol: "BTCUSD", side: "SELL", type: "MARKET", quantity: Decimal.new("1")}

      id1 = Normalize.order_request(params, "BTC-USD").client_order_id
      id2 = Normalize.order_request(params, "BTC-USD").client_order_id

      assert id1 != id2
    end

    test "uppercases side" do
      params = %{symbol: "BTCUSD", side: "sell", type: "MARKET", quantity: Decimal.new("1")}

      assert Normalize.order_request(params, "BTC-USD").side == "SELL"
    end
  end

  describe "order_response/2 (GET order-details shape)" do
    test "limit order: price comes from the echoed order_configuration's limit_price" do
      order = %{
        "order_id" => "11111-00000-000000",
        "client_order_id" => "0000-00000-000000",
        "status" => "OPEN",
        "order_type" => "LIMIT",
        "side" => "BUY",
        "filled_size" => "0.0004",
        "average_filled_price" => "9998.50",
        "order_configuration" => %{
          "limit_limit_gtc" => %{
            "base_size" => "0.001",
            "limit_price" => "10000.00",
            "post_only" => false
          }
        }
      }

      assert Normalize.order_response(order, "BTCUSD") == %{
               "orderId" => "11111-00000-000000",
               "clientOrderId" => "0000-00000-000000",
               "symbol" => "BTCUSD",
               "type" => "LIMIT",
               "side" => "BUY",
               "price" => "10000.00",
               "origQty" => "0.001",
               "executedQty" => "0.0004",
               "status" => "PARTIALLY_FILLED",
               "timeInForce" => "GTC"
             }
    end

    test "market order: price falls back to average_filled_price (no limit_price in echoed config)" do
      order = %{
        "order_id" => "22222-00000-000000",
        "client_order_id" => "market-order-1",
        "status" => "FILLED",
        "order_type" => "MARKET",
        "side" => "SELL",
        "filled_size" => "0.05",
        "average_filled_price" => "63500.25",
        "order_configuration" => %{
          "market_market_ioc" => %{"base_size" => "0.05"}
        }
      }

      result = Normalize.order_response(order, "BTCUSD")

      assert result["price"] == "63500.25"
      assert result["origQty"] == "0.05"
      assert result["status"] == "FILLED"
    end

    test "market order pre-fill: nil/zero average_filled_price passes through as-is" do
      order = %{
        "order_id" => "33333",
        "client_order_id" => "market-order-2",
        "status" => "PENDING",
        "order_type" => "MARKET",
        "side" => "BUY",
        "filled_size" => "0",
        "average_filled_price" => nil,
        "order_configuration" => %{
          "market_market_ioc" => %{"base_size" => "0.01"}
        }
      }

      result = Normalize.order_response(order, "BTCUSD")

      assert result["price"] == nil
      assert result["status"] == "NEW"
    end

    test "origQty reads quote_size when that's the key actually present in the echoed config" do
      order = %{
        "order_id" => "44444",
        "client_order_id" => "quote-sized",
        "status" => "OPEN",
        "order_type" => "MARKET",
        "side" => "BUY",
        "filled_size" => "0",
        "average_filled_price" => nil,
        "order_configuration" => %{
          "market_market_ioc" => %{"quote_size" => "500.00"}
        }
      }

      assert Normalize.order_response(order, "BTCUSD")["origQty"] == "500.00"
    end

    test "hardcodes timeInForce to GTC" do
      order = %{
        "order_id" => "55555",
        "client_order_id" => "id",
        "status" => "FILLED",
        "order_type" => "MARKET",
        "side" => "BUY",
        "filled_size" => "1",
        "average_filled_price" => "100",
        "order_configuration" => %{"market_market_ioc" => %{"base_size" => "1"}}
      }

      assert Normalize.order_response(order, "BTCUSD")["timeInForce"] == "GTC"
    end
  end

  describe "cancel_response/2 (batch_cancel results[] entry)" do
    test "success: true returns {:ok, binance-shaped cancel confirmation}" do
      entry = %{
        "success" => true,
        "failure_reason" => "UNKNOWN_CANCEL_FAILURE_REASON",
        "order_id" => "0000-00000"
      }

      assert Normalize.cancel_response(entry, "BTCUSD") ==
               {:ok, %{"orderId" => "0000-00000", "status" => "CANCELED", "symbol" => "BTCUSD"}}
    end

    test "success: false returns {:error, failure_reason} -- a normal per-order outcome" do
      entry = %{
        "success" => false,
        "failure_reason" => "ORDER_IS_FULLY_FILLED",
        "order_id" => "1111-11111"
      }

      assert Normalize.cancel_response(entry, "BTCUSD") == {:error, "ORDER_IS_FULLY_FILLED"}
    end
  end

  describe "account_response/1 (flattened, already-paginated accounts list)" do
    test "maps currency/available_balance.value/hold.value to asset/free/locked" do
      accounts = [
        %{
          "uuid" => "some-uuid",
          "currency" => "BTC",
          "available_balance" => %{"value" => "1.2435", "currency" => "BTC"},
          "hold" => %{"value" => "0.8423", "currency" => "BTC"},
          "type" => "ACCOUNT_TYPE_CRYPTO",
          "active" => true,
          "ready" => true
        }
      ]

      assert Normalize.account_response(accounts) == %{
               "balances" => [%{"asset" => "BTC", "free" => "1.2435", "locked" => "0.8423"}]
             }
    end

    test "handles multiple accounts (live-confirmed sandbox shape)" do
      accounts = [
        %{
          "uuid" => "66f975a6-bb2e-44be-82e9-cd8669e404b0",
          "name" => "USDC Wallet",
          "currency" => "USDC",
          "available_balance" => %{"value" => "100", "currency" => "USDC"},
          "default" => true,
          "active" => true,
          "created_at" => "2023-12-14T21:40:32.181Z",
          "updated_at" => "2023-12-19T18:21:42.850Z",
          "deleted_at" => nil,
          "type" => "ACCOUNT_TYPE_CRYPTO",
          "ready" => true,
          "hold" => %{"value" => "0", "currency" => "USDC"},
          "platform" => "ACCOUNT_PLATFORM_CONSUMER"
        },
        %{
          "uuid" => "some-other-uuid",
          "currency" => "ETH",
          "available_balance" => %{"value" => "3.5", "currency" => "ETH"},
          "hold" => %{"value" => "0.1", "currency" => "ETH"}
        }
      ]

      result = Normalize.account_response(accounts)
      balances = Map.new(result["balances"], &{&1["asset"], &1})

      assert balances["USDC"] == %{"asset" => "USDC", "free" => "100", "locked" => "0"}
      assert balances["ETH"] == %{"asset" => "ETH", "free" => "3.5", "locked" => "0.1"}
    end

    test "returns an empty balances list for an empty accounts list" do
      assert Normalize.account_response([]) == %{"balances" => []}
    end
  end

  describe "exchange_info/2" do
    test "builds a SymbolInfo-compatible single-symbol exchangeInfo map" do
      info = %{
        base_increment: "0.00000001",
        quote_increment: "0.01",
        base_min_size: "0.00000001"
      }

      assert Normalize.exchange_info(info, "BTCUSD") == %{
               "symbols" => [
                 %{
                   "symbol" => "BTCUSD",
                   "filters" => [
                     %{"filterType" => "PRICE_FILTER", "tickSize" => "0.01"},
                     %{
                       "filterType" => "LOT_SIZE",
                       "stepSize" => "0.00000001",
                       "minQty" => "0.00000001"
                     }
                   ]
                 }
               ]
             }
    end
  end

  describe "ticker_event/2" do
    # Coinbase's own canonical WS ticker channel push example (verified
    # notes §4), one events[].tickers[] item.
    @coinbase_ticker %{
      "type" => "ticker",
      "product_id" => "BTC-USD",
      "price" => "21932.98",
      "volume_24_h" => "16038.28770938",
      "low_24_h" => "21835.29",
      "high_24_h" => "23011.18",
      "low_52_w" => "15460",
      "high_52_w" => "48240",
      "price_percent_chg_24_h" => "-4.15775596190603",
      "best_bid" => "21931.98",
      "best_bid_quantity" => "8000.21",
      "best_ask" => "21933.98",
      "best_ask_quantity" => "8038.07770938"
    }

    test "maps to the Binance 24hrTicker key contract, q and o left nil, no to_string needed" do
      assert Normalize.ticker_event(@coinbase_ticker, "BTCUSD") == %{
               "e" => "24hrTicker",
               "s" => "BTCUSD",
               "c" => "21932.98",
               "o" => nil,
               "h" => "23011.18",
               "l" => "21835.29",
               "v" => "16038.28770938",
               "q" => nil
             }
    end
  end

  describe "execution_report/3" do
    # Coinbase's own canonical WS user channel order event (verified
    # notes §4) -- note there is NO "side" key at all, only "order_side".
    @coinbase_order_event %{
      "avg_price" => "50000",
      "cancel_reason" => "",
      "client_order_id" => "XXX",
      "completion_percentage" => "100.00",
      "contract_expiry_type" => "UNKNOWN_CONTRACT_EXPIRY_TYPE",
      "cumulative_quantity" => "0.01",
      "filled_value" => "500",
      "leaves_quantity" => "0",
      "limit_price" => "50000",
      "number_of_fills" => "1",
      "order_id" => "YYY",
      "order_side" => "BUY",
      "order_type" => "Limit",
      "outstanding_hold_amount" => "0",
      "post_only" => "false",
      "product_id" => "BTC-USD",
      "product_type" => "SPOT",
      "reject_reason" => "",
      "status" => "FILLED",
      "stop_price" => "",
      "time_in_force" => "GOOD_UNTIL_CANCELLED",
      "total_fees" => "2",
      "total_value_after_fees" => "502",
      "trigger_status" => "INVALID_ORDER_TYPE",
      "creation_time" => "2024-06-21T18:29:13.909347Z"
    }

    test "maps a full fill (from zero prev_cum_qty) to the Binance executionReport key contract" do
      assert Normalize.execution_report(@coinbase_order_event, "BTCUSD", Decimal.new(0)) == %{
               "e" => "executionReport",
               "i" => "YYY",
               "s" => "BTCUSD",
               "S" => "BUY",
               "X" => "FILLED",
               "x" => "TRADE",
               "l" => "0.01",
               "L" => "50000",
               "z" => "0.01",
               "q" => "0.01"
             }
    end

    test "reads order_side, NOT side -- a conflicting side key is never read (field-name trap)" do
      decoy = Map.put(@coinbase_order_event, "side", "SELL")

      result = Normalize.execution_report(decoy, "BTCUSD", Decimal.new(0))

      assert result["S"] == "BUY"
    end

    test "derives \"l\" as a cumulative_quantity delta against a nonzero prev_cum_qty" do
      partial_fill = %{
        @coinbase_order_event
        | "status" => "OPEN",
          "cumulative_quantity" => "0.006",
          "leaves_quantity" => "0.004"
      }

      result = Normalize.execution_report(partial_fill, "BTCUSD", Decimal.new("0.002"))

      assert result["l"] == "0.004"
      assert result["z"] == "0.006"
    end

    test "derives \"q\" (orig qty) as cumulative_quantity + leaves_quantity" do
      partial_fill = %{
        @coinbase_order_event
        | "status" => "OPEN",
          "cumulative_quantity" => "0.006",
          "leaves_quantity" => "0.004"
      }

      result = Normalize.execution_report(partial_fill, "BTCUSD", Decimal.new("0.002"))

      # Decimal.add/2 preserves the operands' combined scale (0.006 + 0.004
      # -> "0.010", not "0.01") -- assert numeric equality via Decimal, not
      # a literal string match, since the trailing zero is expected/correct
      # Decimal behavior, not a bug.
      assert Decimal.equal?(Decimal.new(result["q"]), Decimal.new("0.01"))
      assert result["X"] == "PARTIALLY_FILLED"
    end

    test "the same order_id normalized twice with different prev_cum_qty inputs yields different deltas" do
      first_push = %{
        @coinbase_order_event
        | "status" => "OPEN",
          "cumulative_quantity" => "0.003",
          "leaves_quantity" => "0.007"
      }

      second_push = %{
        @coinbase_order_event
        | "status" => "OPEN",
          "cumulative_quantity" => "0.006",
          "leaves_quantity" => "0.004"
      }

      first_result = Normalize.execution_report(first_push, "BTCUSD", Decimal.new(0))
      # CoinbasePrivateStream would now track last_cum_qty["YYY"] = 0.003
      second_result =
        Normalize.execution_report(second_push, "BTCUSD", Decimal.new("0.003"))

      assert first_result["l"] == "0.003"
      assert second_result["l"] == "0.003"
      assert first_result["z"] != second_result["z"]
    end

    test "a fresh new order push (zero cumulative, zero prev) derives exec type NEW" do
      new_push = %{
        @coinbase_order_event
        | "status" => "OPEN",
          "cumulative_quantity" => "0",
          "leaves_quantity" => "1.0"
      }

      result = Normalize.execution_report(new_push, "BTCUSD", Decimal.new(0))

      assert result["x"] == "NEW"
      assert result["X"] == "NEW"
      assert result["l"] == "0"
    end

    test "CANCELLED (double-L) status maps X and x to CANCELED" do
      canceled = %{@coinbase_order_event | "status" => "CANCELLED"}

      result = Normalize.execution_report(canceled, "BTCUSD", Decimal.new("0.005"))

      assert result["X"] == "CANCELED"
      assert result["x"] == "CANCELED"
    end

    test "\"L\" is avg_price (a cumulative average, not a true last-fill price)" do
      assert Normalize.execution_report(@coinbase_order_event, "BTCUSD", Decimal.new(0))["L"] ==
               "50000"
    end
  end
end
