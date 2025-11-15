defmodule TradingEngine.RiskManagerTest do
  use ExUnit.Case, async: true
  alias TradingEngine.RiskManager

  describe "check_order_size/1" do
    test "allows order within size limit" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"  # Below 0.1 BTC limit
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "rejects order exceeding size limit" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.15"  # Above 0.1 BTC limit
      }

      state = %{positions: %{}}

      assert {:error, message} = RiskManager.check_order(order_params, state)
      assert message =~ "Order size exceeds maximum"
    end

    test "allows order exactly at size limit" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.1"  # Exactly at limit
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end
  end

  describe "check_position_size/2" do
    test "allows BUY when no existing positions" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "allows BUY when total position would be within limit" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"
      }

      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: Decimal.new("0.5")}
        }
      }

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "rejects BUY when total position would exceed limit" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.1"  # Within order size limit
      }

      # Already have 0.95 BTC position, adding 0.1 would exceed 1.0 limit
      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: Decimal.new("0.95")}
        }
      }

      assert {:error, message} = RiskManager.check_order(order_params, state)
      assert message =~ "Position size would exceed maximum"
    end

    test "allows SELL regardless of position size" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.05"  # Within order size limit
      }

      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: Decimal.new("0.8")}
        }
      }

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "calculates total position size across multiple symbols" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.08"  # Within order size limit
      }

      # Already have 0.47 BTC + 0.47 ETH (calculated as BTC equivalent)
      # Total: 0.94, adding 0.08 would be 1.02, exceeding 1.0 limit
      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: Decimal.new("0.47")},
          "ETHUSDT" => %{quantity: Decimal.new("0.47")}
        }
      }

      assert {:error, message} = RiskManager.check_order(order_params, state)
      assert message =~ "Position size would exceed maximum"
    end
  end

  describe "combined risk checks" do
    test "order must pass all checks" do
      # Order size is OK (0.05), but would exceed position limit
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"
      }

      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: Decimal.new("0.97")}
        }
      }

      # Should fail on position size check
      assert {:error, message} = RiskManager.check_order(order_params, state)
      assert message =~ "Position size would exceed maximum"
    end

    test "order size check fails before position check" do
      # Order size exceeds limit
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.2"  # Exceeds 0.1 limit
      }

      state = %{positions: %{}}

      assert {:error, message} = RiskManager.check_order(order_params, state)
      assert message =~ "Order size exceeds maximum"
    end
  end

  describe "edge cases" do
    test "handles decimal precision correctly" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.099999999"  # Just below limit
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "handles string quantities" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"  # String format
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "handles empty positions map" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.09"
      }

      state = %{positions: %{}}

      assert :ok = RiskManager.check_order(order_params, state)
    end

    test "handles position with nil quantity" do
      order_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.05"
      }

      state = %{
        positions: %{
          "BTCUSDT" => %{quantity: nil}
        }
      }

      assert :ok = RiskManager.check_order(order_params, state)
    end
  end
end
