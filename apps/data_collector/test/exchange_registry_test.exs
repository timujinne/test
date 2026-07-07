defmodule DataCollector.ExchangeRegistryTest do
  use ExUnit.Case, async: true

  alias DataCollector.ExchangeRegistry

  describe "client_for/1" do
    test "resolves \"binance\" to DataCollector.BinanceClient" do
      assert {:ok, DataCollector.BinanceClient} = ExchangeRegistry.client_for("binance")
    end

    test "returns an error for an unsupported exchange" do
      assert {:error, {:unsupported_exchange, "kraken"}} =
               ExchangeRegistry.client_for("kraken")
    end

    test "returns an error for garbage input" do
      assert {:error, {:unsupported_exchange, "not_a_real_exchange"}} =
               ExchangeRegistry.client_for("not_a_real_exchange")
    end
  end
end
