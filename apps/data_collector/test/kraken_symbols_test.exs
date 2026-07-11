defmodule DataCollector.KrakenSymbolsTest do
  # async: false — the "cached lookups" describe block below mutates the
  # global `:data_collector, :kraken` application env (restored via
  # on_exit/1); keeping this module synchronous avoids racing other test
  # modules that read the same config concurrently (same rationale as
  # DataCollector.OKX.AuthTest's "omits x-simulated-trading..." test).
  use ExUnit.Case, async: false

  alias DataCollector.Kraken.Symbols

  # Canned fixture built from the three live-verified examples in
  # docs/superpowers/notes/kraken-api-verified.md §3 (BTC/USDT, BTC/USD,
  # ETH/BTC), plus one non-`online` entry to prove filtering. Envelope
  # shape per GET /0/public/AssetPairs (verified notes §2/§3). Pure
  # parsing/lookup only — no live HTTP involved.
  @fixture %{
    "error" => [],
    "result" => %{
      "XBTUSDT" => %{
        "altname" => "XBTUSDT",
        "wsname" => "XBT/USDT",
        "base" => "XXBT",
        "quote" => "USDT",
        "pair_decimals" => 1,
        "lot_decimals" => 8,
        "ordermin" => "0.00005",
        "tick_size" => "0.1",
        "status" => "online"
      },
      "XXBTZUSD" => %{
        "altname" => "XBTUSD",
        "wsname" => "XBT/USD",
        "base" => "XXBT",
        "quote" => "ZUSD",
        "pair_decimals" => 1,
        "lot_decimals" => 8,
        "ordermin" => "0.00005",
        "tick_size" => "0.1",
        "status" => "online"
      },
      "XETHXXBT" => %{
        "altname" => "ETHXBT",
        "wsname" => "ETH/XBT",
        "base" => "XETH",
        "quote" => "XXBT",
        "pair_decimals" => 6,
        "lot_decimals" => 8,
        "ordermin" => "0.001",
        "tick_size" => "0.000001",
        "status" => "online"
      },
      "XXDGZUSD" => %{
        "altname" => "XDGUSD",
        "wsname" => "XDG/USD",
        "base" => "XXDG",
        "quote" => "ZUSD",
        "pair_decimals" => 5,
        "lot_decimals" => 2,
        "ordermin" => "60",
        "tick_size" => "0.00001",
        "status" => "cancel_only"
      }
    }
  }

  describe "parse_instruments/1" do
    test "maps online pairs to {concat, altname, pair_id, ws_symbol, info} tuples" do
      result = Symbols.parse_instruments(@fixture)

      assert {"BTCUSDT", "XBTUSDT", "XBTUSDT", "BTC/USDT",
              %{tick_size: "0.1", step_size: "0.00000001", min_qty: "0.00005"}} in result

      assert {"BTCUSD", "XBTUSD", "XXBTZUSD", "BTC/USD",
              %{tick_size: "0.1", step_size: "0.00000001", min_qty: "0.00005"}} in result

      assert {"ETHBTC", "ETHXBT", "XETHXXBT", "ETH/BTC",
              %{tick_size: "0.000001", step_size: "0.00000001", min_qty: "0.001"}} in result
    end

    test "filters out non-online pairs" do
      result = Symbols.parse_instruments(@fixture)

      refute Enum.any?(result, fn {concat, _, _, _, _} -> concat == "DOGEUSD" end)
    end

    test "returns exactly the three online entries for the fixture" do
      assert length(Symbols.parse_instruments(@fixture)) == 3
    end

    test "returns an empty list for a response with no result" do
      assert Symbols.parse_instruments(%{"error" => ["EGeneral:Invalid arguments"]}) == []
    end

    test "returns an empty list for a malformed/unexpected response shape" do
      assert Symbols.parse_instruments(%{}) == []
    end

    test "skips entries missing required fields instead of raising" do
      malformed = %{
        "result" => %{
          "BADPAIR" => %{"altname" => "BAD", "status" => "online"},
          "XETHXXBT" => @fixture["result"]["XETHXXBT"]
        }
      }

      assert [{"ETHBTC", "ETHXBT", "XETHXXBT", "ETH/BTC", _info}] =
               Symbols.parse_instruments(malformed)
    end

    test "falls back to 10^-pair_decimals when tick_size is absent" do
      entry = %{
        "result" => %{
          "XBTUSDT" => Map.delete(@fixture["result"]["XBTUSDT"], "tick_size")
        }
      }

      assert [{_, _, _, _, %{tick_size: "0.1"}}] = Symbols.parse_instruments(entry)
    end
  end

  describe "asset_code_to_ticker/1" do
    test "matches the notes' worked examples exactly" do
      assert Symbols.asset_code_to_ticker("XXBT") == "BTC"
      assert Symbols.asset_code_to_ticker("ZUSD") == "USD"
      assert Symbols.asset_code_to_ticker("USDT") == "USDT"
    end

    test "strips other legacy X/Z prefixes without XBT/XDG substitution" do
      assert Symbols.asset_code_to_ticker("XETH") == "ETH"
      assert Symbols.asset_code_to_ticker("XXRP") == "XRP"
      assert Symbols.asset_code_to_ticker("ZEUR") == "EUR"
    end

    test "applies the XDG->DOGE substitution" do
      assert Symbols.asset_code_to_ticker("XXDG") == "DOGE"
    end

    test "passes through codes with no known prefix unchanged" do
      assert Symbols.asset_code_to_ticker("ADA") == "ADA"
      assert Symbols.asset_code_to_ticker("SOL") == "SOL"
    end
  end

  describe "cached lookups (to_pair/1, to_concat/1, to_ws_symbol/1, instrument_info/1)" do
    setup do
      # A lookup miss on an already-warm cache triggers exactly one refresh
      # attempt (in case the symbol was newly listed — see the moduledoc),
      # which would otherwise be a live network call to Kraken's real API.
      # Point base_url at an unroutable loopback port instead: the HTTP GET
      # fails instantly with `econnrefused` (no packet ever reaches a real
      # host), `refresh/1` logs a warning and leaves the cache untouched,
      # and the lookup correctly falls through to `{:error, :unknown_symbol}`
      # — deterministic, network-free, no live Kraken call involved.
      original = Application.get_env(:data_collector, :kraken, [])

      Application.put_env(
        :data_collector,
        :kraken,
        Keyword.put(original, :base_url, "http://127.0.0.1:1")
      )

      on_exit(fn -> Application.put_env(:data_collector, :kraken, original) end)

      # DataCollector.Kraken.Symbols is supervised by DataCollector.Application
      # (same as DataCollector.OKX.Symbols), so it's already running by the
      # time the test suite boots — no start_supervised! here (that would
      # conflict with the already-registered name).
      @fixture
      |> Symbols.parse_instruments()
      |> Enum.each(&Symbols.cache_entry/1)

      # Mark the cache as already warm so lookups for symbols present in
      # the fixture resolve straight from ETS without any refresh attempt.
      :sys.replace_state(DataCollector.Kraken.Symbols, fn state -> %{state | loaded?: true} end)

      :ok
    end

    test "to_pair/1 resolves concat -> altname (native Kraken form, untranslated)" do
      assert Symbols.to_pair("BTCUSD") == {:ok, "XBTUSD"}
      assert Symbols.to_pair("BTCUSDT") == {:ok, "XBTUSDT"}
      assert Symbols.to_pair("ETHBTC") == {:ok, "ETHXBT"}
    end

    test "to_concat/1 resolves from altname input" do
      assert Symbols.to_concat("XBTUSD") == {:ok, "BTCUSD"}
      assert Symbols.to_concat("XBTUSDT") == {:ok, "BTCUSDT"}
      assert Symbols.to_concat("ETHXBT") == {:ok, "ETHBTC"}
    end

    test "to_concat/1 resolves from pair-id input" do
      assert Symbols.to_concat("XXBTZUSD") == {:ok, "BTCUSD"}
      assert Symbols.to_concat("XBTUSDT") == {:ok, "BTCUSDT"}
      assert Symbols.to_concat("XETHXXBT") == {:ok, "ETHBTC"}
    end

    test "to_ws_symbol/1 resolves concat -> WS v2 symbol" do
      assert Symbols.to_ws_symbol("BTCUSD") == {:ok, "BTC/USD"}
      assert Symbols.to_ws_symbol("BTCUSDT") == {:ok, "BTC/USDT"}
      assert Symbols.to_ws_symbol("ETHBTC") == {:ok, "ETH/BTC"}
    end

    test "instrument_info/1 resolves concat -> tick_size/step_size/min_qty" do
      assert Symbols.instrument_info("BTCUSD") ==
               {:ok, %{tick_size: "0.1", step_size: "0.00000001", min_qty: "0.00005"}}

      assert Symbols.instrument_info("ETHBTC") ==
               {:ok, %{tick_size: "0.000001", step_size: "0.00000001", min_qty: "0.001"}}
    end

    test "returns {:error, :unknown_symbol} for an unrecognized concat/pair" do
      assert Symbols.to_pair("DOGEUSD") == {:error, :unknown_symbol}
      assert Symbols.to_concat("NOPE") == {:error, :unknown_symbol}
      assert Symbols.to_ws_symbol("XRPUSD") == {:error, :unknown_symbol}
      assert Symbols.instrument_info("XRPUSD") == {:error, :unknown_symbol}
    end
  end
end
