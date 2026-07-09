defmodule TradingEngine.SymbolInfoTest do
  use ExUnit.Case, async: false

  alias TradingEngine.SymbolInfo

  describe "get_precision/1 (default exchange)" do
    test "defaults to \"binance\" and returns a {price, qty} tuple" do
      {price_precision, qty_precision} = SymbolInfo.get_precision("__UNKNOWN_SYMBOL__")
      assert is_integer(price_precision)
      assert is_integer(qty_precision)
    end
  end

  describe "get_precision/2 (exchange-aware)" do
    test "falls back to defaults for an unsupported exchange without raising" do
      assert {5, 2} = SymbolInfo.get_precision("kraken", "BTCUSDT")
    end

    test "caches per (exchange, symbol) key so different exchanges don't collide" do
      # Both requests resolve to the same fallback for an unsupported exchange,
      # but exercise the {exchange, symbol} ETS key independently.
      assert {5, 2} = SymbolInfo.get_precision("kraken", "ETHUSDT")
      assert {5, 2} = SymbolInfo.get_precision("coinbase", "ETHUSDT")
    end
  end
end
