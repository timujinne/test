defmodule BinanceSystemTest do
  use ExUnit.Case
  doctest BinanceSystem

  test "returns application version" do
    version = BinanceSystem.version()
    assert is_binary(version)
    assert version == "0.1.0"
  end
end
