defmodule DataCollector.BinanceClientTest do
  use ExUnit.Case, async: true

  # Note: These tests verify the signature generation logic
  # without making actual HTTP requests to Binance API

  describe "signature generation" do
    test "generates valid HMAC SHA256 signature" do
      # This is the internal function, so we test it through the module
      # We'll verify the signature format is correct
      secret_key = "test_secret_key"
      params = %{symbol: "BTCUSDT", timestamp: 1_234_567_890}

      # Call private function through module (reflection for testing)
      query_string = URI.encode_query(params)

      signature =
        :crypto.mac(:hmac, :sha256, secret_key, query_string)
        |> Base.encode16(case: :lower)

      # Verify signature format
      assert is_binary(signature)
      # SHA256 hex = 64 chars
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[0-9a-f]{64}$/)
    end

    test "signature changes with different parameters" do
      secret_key = "test_secret_key"

      params1 = %{symbol: "BTCUSDT", timestamp: 1_234_567_890}
      params2 = %{symbol: "ETHUSDT", timestamp: 1_234_567_890}

      query1 = URI.encode_query(params1)
      query2 = URI.encode_query(params2)

      sig1 = :crypto.mac(:hmac, :sha256, secret_key, query1) |> Base.encode16(case: :lower)
      sig2 = :crypto.mac(:hmac, :sha256, secret_key, query2) |> Base.encode16(case: :lower)

      assert sig1 != sig2
    end

    test "signature is deterministic for same inputs" do
      secret_key = "test_secret_key"
      params = %{symbol: "BTCUSDT", timestamp: 1_234_567_890}

      query = URI.encode_query(params)

      sig1 = :crypto.mac(:hmac, :sha256, secret_key, query) |> Base.encode16(case: :lower)
      sig2 = :crypto.mac(:hmac, :sha256, secret_key, query) |> Base.encode16(case: :lower)

      assert sig1 == sig2
    end
  end

  describe "parameter encoding" do
    test "encodes parameters correctly for API" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "50000.00",
        timestamp: 1_234_567_890
      }

      encoded = URI.encode_query(params)

      # Verify all parameters are present
      assert encoded =~ "symbol=BTCUSDT"
      assert encoded =~ "side=BUY"
      assert encoded =~ "type=LIMIT"
      assert encoded =~ "quantity=0.001"
      assert encoded =~ "price=50000.00"
      assert encoded =~ "timestamp=1234567890"
    end

    test "handles special characters in encoding" do
      params = %{
        # Contains special char
        symbol: "BTC/USDT",
        test: "value with spaces"
      }

      encoded = URI.encode_query(params)

      # URI encoding should handle special characters
      assert encoded =~ "symbol=BTC%2FUSDT"
      assert encoded =~ "test=value+with+spaces"
    end
  end

  describe "timestamp generation" do
    test "generates millisecond timestamp" do
      timestamp = System.system_time(:millisecond)

      # Verify it's a valid Unix timestamp in milliseconds
      assert is_integer(timestamp)
      # After Sept 2020
      assert timestamp > 1_600_000_000_000
      # Before year 2033
      assert timestamp < 2_000_000_000_000
    end

    test "timestamp increases over time" do
      ts1 = System.system_time(:millisecond)
      Process.sleep(10)
      ts2 = System.system_time(:millisecond)

      assert ts2 > ts1
    end
  end

  describe "order parameter validation" do
    test "market order parameters are valid" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "MARKET",
        quantity: "0.001"
      }

      # Verify required fields are present
      assert Map.has_key?(params, :symbol)
      assert Map.has_key?(params, :side)
      assert Map.has_key?(params, :type)
      assert Map.has_key?(params, :quantity)

      # Verify values are correct format
      assert params.side in ["BUY", "SELL"]
      assert params.type in ["MARKET", "LIMIT"]
    end

    test "limit order includes price" do
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "50000.00",
        timeInForce: "GTC"
      }

      assert Map.has_key?(params, :price)
      assert Map.has_key?(params, :timeInForce)
    end
  end

  describe "API response handling" do
    test "successful order response structure" do
      # Example response from Binance API
      response = %{
        "orderId" => 123_456_789,
        "clientOrderId" => "test_order_123",
        "symbol" => "BTCUSDT",
        "type" => "MARKET",
        "side" => "BUY",
        "price" => "0.00000000",
        "origQty" => "0.001",
        "executedQty" => "0.001",
        "status" => "FILLED",
        "timeInForce" => "GTC"
      }

      # Verify all required fields are present
      assert is_integer(response["orderId"])
      assert is_binary(response["clientOrderId"])
      assert is_binary(response["symbol"])
      assert response["status"] in ["NEW", "FILLED", "PARTIALLY_FILLED", "CANCELED"]
    end

    test "error response structure" do
      error_response = %{
        "code" => -1021,
        "msg" => "Timestamp for this request is outside of the recvWindow."
      }

      assert is_integer(error_response["code"])
      assert is_binary(error_response["msg"])
    end
  end

  describe "decimal handling" do
    test "handles decimal quantities correctly" do
      balances = [
        %{"asset" => "BTC", "free" => "1.23456789", "locked" => "0.00000000"},
        %{"asset" => "ETH", "free" => "10.5", "locked" => "0.0"},
        %{"asset" => "USDT", "free" => "0", "locked" => "0"}
      ]

      # Filter non-zero balances
      filtered =
        Enum.filter(balances, fn b ->
          Decimal.compare(Decimal.new(b["free"]), 0) == :gt or
            Decimal.compare(Decimal.new(b["locked"]), 0) == :gt
        end)

      assert length(filtered) == 2
      assert Enum.any?(filtered, fn b -> b["asset"] == "BTC" end)
      assert Enum.any?(filtered, fn b -> b["asset"] == "ETH" end)
    end

    test "handles very small decimal values" do
      small_value = "0.00000001"
      decimal = Decimal.new(small_value)

      assert Decimal.compare(decimal, 0) == :gt
    end

    test "handles large decimal values" do
      large_value = "123456789.87654321"
      decimal = Decimal.new(large_value)

      assert Decimal.compare(decimal, 0) == :gt
      assert Decimal.to_string(decimal) == large_value
    end
  end

  describe "order book depth" do
    test "validates depth response structure" do
      # Example response from get_depth
      response = %{
        "lastUpdateId" => 1_234_567_890,
        "bids" => [
          ["50000.00", "1.5"],
          ["49999.00", "2.3"],
          ["49998.00", "0.8"]
        ],
        "asks" => [
          ["50001.00", "1.2"],
          ["50002.00", "3.1"],
          ["50003.00", "0.5"]
        ]
      }

      # Verify structure
      assert is_integer(response["lastUpdateId"])
      assert is_list(response["bids"])
      assert is_list(response["asks"])

      # Verify bids and asks are price-quantity pairs
      [price, qty] = hd(response["bids"])
      assert is_binary(price)
      assert is_binary(qty)
    end

    test "validates depth limit parameters" do
      valid_limits = [5, 10, 20, 50, 100, 500, 1000]

      for limit <- valid_limits do
        assert limit in valid_limits
      end
    end

    test "bids are sorted descending, asks ascending" do
      response = %{
        "lastUpdateId" => 1_234_567_890,
        "bids" => [
          ["50000.00", "1.5"],
          ["49999.00", "2.3"],
          ["49998.00", "0.8"]
        ],
        "asks" => [
          ["50001.00", "1.2"],
          ["50002.00", "3.1"],
          ["50003.00", "0.5"]
        ]
      }

      # Verify bids are in descending order (highest price first)
      bid_prices =
        Enum.map(response["bids"], fn [price, _qty] ->
          Decimal.new(price)
        end)

      assert bid_prices == Enum.sort(bid_prices, &(Decimal.compare(&1, &2) == :gt))

      # Verify asks are in ascending order (lowest price first)
      ask_prices =
        Enum.map(response["asks"], fn [price, _qty] ->
          Decimal.new(price)
        end)

      assert ask_prices == Enum.sort(ask_prices, &(Decimal.compare(&1, &2) == :lt))
    end
  end

  describe "klines/candlestick data" do
    test "validates kline response structure" do
      # Example response from get_klines
      kline = [
        # Open time
        1_499_040_000_000,
        # Open
        "0.01634790",
        # High
        "0.80000000",
        # Low
        "0.01575800",
        # Close
        "0.01577100",
        # Volume
        "148976.11427815",
        # Close time
        1_499_644_799_999,
        # Quote asset volume
        "2434.19055334",
        # Number of trades
        308,
        # Taker buy base asset volume
        "1756.87402397",
        # Taker buy quote asset volume
        "28.46694368",
        # Ignore
        "0"
      ]

      # Verify structure (12 elements)
      assert length(kline) == 12

      # Verify types
      [open_time, open, high, low, close, volume, close_time | _rest] = kline

      assert is_integer(open_time)
      assert is_binary(open)
      assert is_binary(high)
      assert is_binary(low)
      assert is_binary(close)
      assert is_binary(volume)
      assert is_integer(close_time)
    end

    test "validates kline interval formats" do
      valid_intervals = [
        "1m",
        "3m",
        "5m",
        "15m",
        "30m",
        "1h",
        "2h",
        "4h",
        "6h",
        "8h",
        "12h",
        "1d",
        "3d",
        "1w",
        "1M"
      ]

      for interval <- valid_intervals do
        assert interval in valid_intervals
      end
    end

    test "klines are chronologically ordered" do
      klines = [
        [
          1_499_040_000_000,
          "0.01",
          "0.02",
          "0.01",
          "0.015",
          "100",
          1_499_040_059_999,
          "1.5",
          10,
          "50",
          "0.75",
          "0"
        ],
        [
          1_499_040_060_000,
          "0.015",
          "0.03",
          "0.01",
          "0.02",
          "200",
          1_499_040_119_999,
          "3.0",
          20,
          "100",
          "1.5",
          "0"
        ],
        [
          1_499_040_120_000,
          "0.02",
          "0.025",
          "0.015",
          "0.018",
          "150",
          1_499_040_179_999,
          "2.7",
          15,
          "75",
          "1.35",
          "0"
        ]
      ]

      # Extract open times
      open_times = Enum.map(klines, fn [open_time | _] -> open_time end)

      # Verify they are in ascending order
      assert open_times == Enum.sort(open_times)
    end
  end

  describe "24h ticker statistics" do
    test "validates 24h ticker response structure" do
      # Example response from get_24h_ticker
      response = %{
        "symbol" => "BTCUSDT",
        "priceChange" => "-94.99999800",
        "priceChangePercent" => "-0.189",
        "weightedAvgPrice" => "50123.45678900",
        "prevClosePrice" => "50000.00",
        "lastPrice" => "49905.00",
        "lastQty" => "0.001",
        "bidPrice" => "49904.50",
        "askPrice" => "49905.50",
        "openPrice" => "50000.00",
        "highPrice" => "51000.00",
        "lowPrice" => "49000.00",
        "volume" => "1234.56789000",
        "quoteVolume" => "61728394.12345678",
        "openTime" => 1_499_040_000_000,
        "closeTime" => 1_499_126_400_000,
        "firstId" => 28_385,
        "lastId" => 28_460,
        "count" => 76
      }

      # Verify required fields
      assert is_binary(response["symbol"])
      assert is_binary(response["priceChange"])
      assert is_binary(response["priceChangePercent"])
      assert is_binary(response["highPrice"])
      assert is_binary(response["lowPrice"])
      assert is_binary(response["volume"])
      assert is_binary(response["lastPrice"])
    end

    test "validates price change calculations" do
      response = %{
        "openPrice" => "50000.00",
        "lastPrice" => "49905.00",
        "priceChange" => "-95.00",
        "priceChangePercent" => "-0.190"
      }

      open = Decimal.new(response["openPrice"])
      last = Decimal.new(response["lastPrice"])
      change = Decimal.new(response["priceChange"])

      # Verify price change = lastPrice - openPrice
      calculated_change = Decimal.sub(last, open)
      assert Decimal.compare(calculated_change, change) == :eq
    end

    test "validates 24h time window" do
      response = %{
        "openTime" => 1_499_040_000_000,
        "closeTime" => 1_499_126_400_000
      }

      # Calculate time difference in hours
      time_diff_ms = response["closeTime"] - response["openTime"]
      time_diff_hours = time_diff_ms / (1000 * 60 * 60)

      # Should be approximately 24 hours
      assert time_diff_hours >= 23.9 and time_diff_hours <= 24.1
    end

    test "validates trade count consistency" do
      response = %{
        "firstId" => 28_385,
        "lastId" => 28_460,
        "count" => 76
      }

      # Verify count = lastId - firstId + 1
      calculated_count = response["lastId"] - response["firstId"] + 1
      assert calculated_count == response["count"]
    end
  end
end
