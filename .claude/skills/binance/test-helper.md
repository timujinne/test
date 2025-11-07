---
name: binance-test-helper
description: Generate test helpers and mocks for Binance API testing
tags: binance, testing, mock, api, cryptocurrency
---

# Binance API Test Helpers

This skill generates comprehensive test helpers and mocks for testing Binance API integrations.

## Step 1: Create Test Support Module

Create file at: `test/support/binance_mock.ex`

```elixir
defmodule BinanceMock do
  @moduledoc """
  Mock responses for Binance API testing.

  Provides realistic mock data for:
  - Account information
  - Market data
  - Order operations
  - WebSocket streams
  """

  # Account Information

  def mock_account_info do
    %{
      "makerCommission" => 10,
      "takerCommission" => 10,
      "buyerCommission" => 0,
      "sellerCommission" => 0,
      "canTrade" => true,
      "canWithdraw" => false,
      "canDeposit" => false,
      "updateTime" => System.system_time(:millisecond),
      "accountType" => "SPOT",
      "balances" => [
        %{"asset" => "BTC", "free" => "10.00000000", "locked" => "0.00000000"},
        %{"asset" => "USDT", "free" => "10000.00000000", "locked" => "0.00000000"},
        %{"asset" => "ETH", "free" => "100.00000000", "locked" => "0.00000000"},
        %{"asset" => "BNB", "free" => "50.00000000", "locked" => "0.00000000"}
      ],
      "permissions" => ["SPOT"]
    }
  end

  # Market Data

  def mock_ticker_price(symbol \\ "BTCUSDT") do
    prices = %{
      "BTCUSDT" => "50000.00",
      "ETHUSDT" => "3000.00",
      "BNBUSDT" => "400.00",
      "ADAUSDT" => "0.50"
    }

    %{
      "symbol" => symbol,
      "price" => Map.get(prices, symbol, "100.00")
    }
  end

  def mock_ticker_24hr(symbol \\ "BTCUSDT") do
    %{
      "symbol" => symbol,
      "priceChange" => "1000.00",
      "priceChangePercent" => "2.04",
      "weightedAvgPrice" => "49500.00",
      "prevClosePrice" => "49000.00",
      "lastPrice" => "50000.00",
      "lastQty" => "0.001",
      "bidPrice" => "49999.00",
      "bidQty" => "1.000",
      "askPrice" => "50001.00",
      "askQty" => "1.000",
      "openPrice" => "49000.00",
      "highPrice" => "51000.00",
      "lowPrice" => "48000.00",
      "volume" => "1000.00",
      "quoteVolume" => "50000000.00",
      "openTime" => System.system_time(:millisecond) - 86_400_000,
      "closeTime" => System.system_time(:millisecond),
      "firstId" => 1_000_000,
      "lastId" => 1_050_000,
      "count" => 50_000
    }
  end

  def mock_order_book(symbol \\ "BTCUSDT") do
    %{
      "lastUpdateId" => 1_234_567_890,
      "bids" => [
        ["49999.00", "1.0"],
        ["49998.00", "2.0"],
        ["49997.00", "1.5"]
      ],
      "asks" => [
        ["50001.00", "1.0"],
        ["50002.00", "2.0"],
        ["50003.00", "1.5"]
      ]
    }
  end

  def mock_klines(symbol \\ "BTCUSDT", interval \\ "1m", limit \\ 10) do
    base_time = System.system_time(:millisecond) - (limit * 60 * 1000)

    Enum.map(0..(limit-1), fn i ->
      open_time = base_time + (i * 60 * 1000)
      close_time = open_time + 59_999

      base_price = 50_000.0
      variation = :rand.uniform() * 100 - 50

      open = Float.to_string(base_price + variation)
      high = Float.to_string(base_price + variation + :rand.uniform() * 50)
      low = Float.to_string(base_price + variation - :rand.uniform() * 50)
      close = Float.to_string(base_price + variation + :rand.uniform() * 20 - 10)
      volume = Float.to_string(:rand.uniform() * 10)

      [
        open_time,
        open,
        high,
        low,
        close,
        volume,
        close_time,
        Float.to_string(:rand.uniform() * 500_000),  # Quote asset volume
        100 + i,  # Number of trades
        Float.to_string(:rand.uniform() * 5),  # Taker buy base asset volume
        Float.to_string(:rand.uniform() * 250_000),  # Taker buy quote asset volume
        "0"  # Ignore
      ]
    end)
  end

  # Order Operations

  def mock_order_response(opts \\ []) do
    symbol = Keyword.get(opts, :symbol, "BTCUSDT")
    side = Keyword.get(opts, :side, "BUY")
    order_type = Keyword.get(opts, :type, "LIMIT")
    price = Keyword.get(opts, :price, "50000.00")
    quantity = Keyword.get(opts, :quantity, "0.001")
    status = Keyword.get(opts, :status, "FILLED")

    %{
      "symbol" => symbol,
      "orderId" => :rand.uniform(1_000_000),
      "orderListId" => -1,
      "clientOrderId" => "test_order_#{System.unique_integer([:positive])}",
      "transactTime" => System.system_time(:millisecond),
      "price" => price,
      "origQty" => quantity,
      "executedQty" => if(status == "FILLED", do: quantity, else: "0.0"),
      "cummulativeQuoteQty" => if(status == "FILLED", do: "50.00", else: "0.0"),
      "status" => status,
      "timeInForce" => "GTC",
      "type" => order_type,
      "side" => side,
      "fills" => if status == "FILLED" do
        [
          %{
            "price" => price,
            "qty" => quantity,
            "commission" => "0.00001",
            "commissionAsset" => "BTC",
            "tradeId" => :rand.uniform(1_000_000)
          }
        ]
      else
        []
      end
    }
  end

  def mock_order_status(order_id) do
    %{
      "symbol" => "BTCUSDT",
      "orderId" => order_id,
      "orderListId" => -1,
      "clientOrderId" => "test_order_#{order_id}",
      "price" => "50000.00",
      "origQty" => "0.001",
      "executedQty" => "0.001",
      "cummulativeQuoteQty" => "50.00",
      "status" => "FILLED",
      "timeInForce" => "GTC",
      "type" => "LIMIT",
      "side" => "BUY",
      "stopPrice" => "0.0",
      "icebergQty" => "0.0",
      "time" => System.system_time(:millisecond) - 60_000,
      "updateTime" => System.system_time(:millisecond),
      "isWorking" => true,
      "origQuoteOrderQty" => "0.0"
    }
  end

  def mock_open_orders do
    [
      mock_order_response(status: "NEW", order_id: 1),
      mock_order_response(status: "PARTIALLY_FILLED", order_id: 2)
    ]
  end

  # WebSocket Messages

  def mock_trade_stream_message(symbol \\ "BTCUSDT") do
    %{
      "e" => "trade",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "t" => :rand.uniform(1_000_000),
      "p" => "50000.00",
      "q" => "0.001",
      "b" => :rand.uniform(1_000_000),
      "a" => :rand.uniform(1_000_000),
      "T" => System.system_time(:millisecond),
      "m" => false,
      "M" => true
    }
  end

  def mock_kline_stream_message(symbol \\ "BTCUSDT") do
    time = System.system_time(:millisecond)

    %{
      "e" => "kline",
      "E" => time,
      "s" => symbol,
      "k" => %{
        "t" => time - 60_000,
        "T" => time,
        "s" => symbol,
        "i" => "1m",
        "f" => 100,
        "L" => 200,
        "o" => "50000.00",
        "c" => "50010.00",
        "h" => "50050.00",
        "l" => "49990.00",
        "v" => "10.0",
        "n" => 100,
        "x" => false,
        "q" => "500000.00",
        "V" => "5.0",
        "Q" => "250000.00",
        "B" => "0"
      }
    }
  end

  def mock_depth_update_message(symbol \\ "BTCUSDT") do
    %{
      "e" => "depthUpdate",
      "E" => System.system_time(:millisecond),
      "s" => symbol,
      "U" => 157,
      "u" => 160,
      "b" => [
        ["49999.00", "1.0"],
        ["49998.00", "2.0"]
      ],
      "a" => [
        ["50001.00", "1.0"],
        ["50002.00", "2.0"]
      ]
    }
  end

  # Error Responses

  def mock_error_response(code \\ -2010, msg \\ "Account has insufficient balance") do
    %{
      "code" => code,
      "msg" => msg
    }
  end

  def mock_rate_limit_error do
    mock_error_response(-1003, "Too many requests")
  end

  # Helper Functions

  def random_symbol do
    Enum.random(["BTCUSDT", "ETHUSDT", "BNBUSDT", "ADAUSDT", "DOGEUSDT"])
  end

  def random_side do
    Enum.random(["BUY", "SELL"])
  end

  def random_order_type do
    Enum.random(["LIMIT", "MARKET", "STOP_LOSS_LIMIT"])
  end
end
```

## Step 2: Create Test Helper Module

Create file at: `test/support/binance_test_helper.ex`

```elixir
defmodule BinanceTestHelper do
  @moduledoc """
  Helper functions for Binance API testing.
  """

  import Mox

  alias BinanceMock

  def setup_binance_mocks(_context) do
    # Setup default mocks
    stub(BinanceClientMock, :get_account, fn -> {:ok, BinanceMock.mock_account_info()} end)
    stub(BinanceClientMock, :get_ticker_price, fn symbol ->
      {:ok, BinanceMock.mock_ticker_price(symbol)}
    end)

    :ok
  end

  def expect_successful_order(symbol \\ "BTCUSDT", side \\ "BUY") do
    expect(BinanceClientMock, :create_order, fn ^symbol, ^side, _type, _opts ->
      {:ok, BinanceMock.mock_order_response(symbol: symbol, side: side)}
    end)
  end

  def expect_order_failure(reason \\ "Insufficient balance") do
    expect(BinanceClientMock, :create_order, fn _symbol, _side, _type, _opts ->
      {:error, BinanceMock.mock_error_response(-2010, reason)}
    end)
  end

  def expect_rate_limit do
    expect(BinanceClientMock, :get_ticker_price, fn _symbol ->
      {:error, BinanceMock.mock_rate_limit_error()}
    end)
  end

  def simulate_websocket_messages(pid, messages, interval \\ 100) do
    Task.start(fn ->
      Enum.each(messages, fn msg ->
        send(pid, {:websocket_message, msg})
        Process.sleep(interval)
      end)
    end)
  end

  def create_test_order(attrs \\ %{}) do
    defaults = %{
      symbol: "BTCUSDT",
      side: "BUY",
      type: "LIMIT",
      price: Decimal.new("50000"),
      quantity: Decimal.new("0.001"),
      status: "NEW"
    }

    Map.merge(defaults, attrs)
  end
end
```

## Step 3: Configure Mox

In `test/test_helper.exs`:

```elixir
# Define mocks
Mox.defmock(BinanceClientMock, for: BinanceClientBehaviour)

# Set default mode
Mox.set_mox_global()

ExUnit.start()
```

## Step 4: Usage in Tests

```elixir
defmodule TradingEngine.TraderTest do
  use ExUnit.Case, async: true

  import Mox
  import BinanceTestHelper

  alias BinanceMock
  alias TradingEngine.Trader

  setup :verify_on_exit!
  setup :setup_binance_mocks

  describe "place_order/3" do
    test "successfully places a buy order" do
      expect_successful_order("BTCUSDT", "BUY")

      assert {:ok, order} = Trader.place_order("BTCUSDT", "BUY", quantity: "0.001")
      assert order["status"] == "FILLED"
    end

    test "handles insufficient balance error" do
      expect_order_failure("Insufficient balance")

      assert {:error, error} = Trader.place_order("BTCUSDT", "BUY", quantity: "100.0")
      assert error["msg"] =~ "Insufficient balance"
    end

    test "handles rate limiting" do
      expect_rate_limit()

      assert {:error, error} = Trader.get_price("BTCUSDT")
      assert error["code"] == -1003
    end
  end

  describe "websocket updates" do
    test "processes trade stream messages" do
      {:ok, pid} = Trader.start_link(symbol: "BTCUSDT")

      message = BinanceMock.mock_trade_stream_message("BTCUSDT")
      send(pid, {:websocket_message, message})

      Process.sleep(50)

      state = :sys.get_state(pid)
      assert state.last_price == Decimal.new(message["p"])
    end
  end
end
```

## Best Practices

1. **Use property-based testing** for edge cases
2. **Test error scenarios** explicitly
3. **Mock WebSocket connections** in tests
4. **Use fixtures** for complex test data
5. **Test rate limiting** behavior
6. **Verify API signatures** in tests
