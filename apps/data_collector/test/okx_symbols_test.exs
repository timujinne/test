defmodule DataCollector.OKXSymbolsTest do
  use ExUnit.Case, async: true

  alias DataCollector.OKX.Symbols

  # Canned fixture modeled on GET /api/v5/public/instruments?instType=SPOT
  # (field names per docs/superpowers/notes/okx-api-verified.md §6). Pure
  # parsing only — no HTTP involved, per Task 3's "no live HTTP" constraint.
  @fixture %{
    "code" => "0",
    "msg" => "",
    "data" => [
      %{
        "instId" => "BTC-USDT",
        "instType" => "SPOT",
        "baseCcy" => "BTC",
        "quoteCcy" => "USDT",
        "tickSz" => "0.1",
        "lotSz" => "0.00000001",
        "minSz" => "0.00001",
        "state" => "live"
      },
      %{
        "instId" => "ETH-USDT",
        "instType" => "SPOT",
        "baseCcy" => "ETH",
        "quoteCcy" => "USDT",
        "tickSz" => "0.01",
        "lotSz" => "0.0001",
        "minSz" => "0.0001",
        "state" => "live"
      },
      %{
        "instId" => "SUSPENDED-USDT",
        "instType" => "SPOT",
        "baseCcy" => "SUSPENDED",
        "quoteCcy" => "USDT",
        "tickSz" => "0.01",
        "lotSz" => "0.01",
        "minSz" => "0.01",
        "state" => "suspend"
      },
      %{
        "instId" => "BTC-USD-SWAP",
        "instType" => "SWAP",
        "baseCcy" => "",
        "quoteCcy" => "",
        "tickSz" => "0.1",
        "lotSz" => "1",
        "minSz" => "1",
        "state" => "live"
      }
    ]
  }

  describe "parse_instruments/1" do
    test "maps live SPOT instruments to {concat, inst_id, info} tuples" do
      result = Symbols.parse_instruments(@fixture)

      assert {"BTCUSDT", "BTC-USDT", %{tick_sz: "0.1", lot_sz: "0.00000001", min_sz: "0.00001"}} in result

      assert {"ETHUSDT", "ETH-USDT", %{tick_sz: "0.01", lot_sz: "0.0001", min_sz: "0.0001"}} in result
    end

    test "filters out non-live instruments" do
      result = Symbols.parse_instruments(@fixture)

      refute Enum.any?(result, fn {concat, _inst_id, _info} -> concat == "SUSPENDEDUSDT" end)
    end

    test "skips entries without base/quote currency (e.g. non-SPOT instruments)" do
      result = Symbols.parse_instruments(@fixture)

      refute Enum.any?(result, fn {_concat, inst_id, _info} -> inst_id == "BTC-USD-SWAP" end)
    end

    test "returns exactly the two well-formed live SPOT entries for the fixture" do
      assert length(Symbols.parse_instruments(@fixture)) == 2
    end

    test "returns an empty list for a response with no data" do
      assert Symbols.parse_instruments(%{"code" => "0", "msg" => "", "data" => []}) == []
    end

    test "returns an empty list for a malformed/unexpected response shape" do
      assert Symbols.parse_instruments(%{"code" => "50000", "msg" => "error"}) == []
      assert Symbols.parse_instruments(%{}) == []
    end

    test "skips entries missing required fields instead of raising" do
      malformed = %{
        "data" => [
          %{"instId" => "BTC-USDT", "state" => "live"},
          %{
            "instId" => "ETH-USDT",
            "baseCcy" => "ETH",
            "quoteCcy" => "USDT",
            "tickSz" => "0.01",
            "lotSz" => "0.0001",
            "minSz" => "0.0001",
            "state" => "live"
          }
        ]
      }

      assert [{"ETHUSDT", "ETH-USDT", _info}] = Symbols.parse_instruments(malformed)
    end
  end
end
