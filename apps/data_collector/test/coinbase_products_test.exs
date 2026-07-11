defmodule DataCollector.CoinbaseProductsTest do
  # async: false — the "cached lookups" describe block below mutates the
  # global `:data_collector, :coinbase` application env (restored via
  # on_exit/1); keeping this module synchronous avoids racing other test
  # modules that read the same config concurrently (same rationale as
  # DataCollector.KrakenSymbolsTest's "cached lookups" describe block).
  use ExUnit.Case, async: false

  alias DataCollector.Coinbase.Products

  # Canned fixture built from the live-verified BTC-USD field example in
  # docs/superpowers/notes/coinbase-api-verified.md §2's Products section,
  # plus a second product to prove multi-entry parsing, plus one
  # `status != "online"` entry to prove filtering. Envelope shape per
  # GET /api/v3/brokerage/market/products?product_type=SPOT. Pure
  # parsing/lookup only — no live HTTP involved.
  @fixture %{
    "products" => [
      %{
        "product_id" => "BTC-USD",
        "base_currency_id" => "BTC",
        "quote_currency_id" => "USD",
        "base_increment" => "0.00000001",
        "quote_increment" => "0.01",
        "price_increment" => "0.01",
        "base_min_size" => "0.00000001",
        "base_max_size" => "3400",
        "quote_min_size" => "1",
        "quote_max_size" => "150000000",
        "status" => "online",
        "trading_disabled" => false,
        "is_disabled" => false,
        "cancel_only" => false,
        "limit_only" => false,
        "post_only" => false,
        "product_type" => "SPOT",
        "price" => "64110.6",
        "base_name" => "Bitcoin",
        "quote_name" => "US Dollar"
      },
      %{
        "product_id" => "ETH-USD",
        "base_currency_id" => "ETH",
        "quote_currency_id" => "USD",
        "base_increment" => "0.00000001",
        "quote_increment" => "0.01",
        "base_min_size" => "0.0001",
        "status" => "online",
        "product_type" => "SPOT"
      },
      %{
        "product_id" => "DELISTED-USD",
        "base_currency_id" => "DELISTED",
        "quote_currency_id" => "USD",
        "base_increment" => "0.01",
        "quote_increment" => "0.01",
        "base_min_size" => "0.01",
        "status" => "delisted",
        "product_type" => "SPOT"
      }
    ],
    "has_next" => false,
    "cursor" => "",
    "num_products" => 3
  }

  describe "parse_products/1" do
    test "maps online SPOT products to {concat, product_id, info} tuples" do
      result = Products.parse_products(@fixture)

      assert {"BTCUSD", "BTC-USD",
              %{
                base_increment: "0.00000001",
                quote_increment: "0.01",
                base_min_size: "0.00000001"
              }} in result

      assert {"ETHUSD", "ETH-USD",
              %{base_increment: "0.00000001", quote_increment: "0.01", base_min_size: "0.0001"}} in result
    end

    test "filters out non-online products" do
      result = Products.parse_products(@fixture)

      refute Enum.any?(result, fn {concat, _, _} -> concat == "DELISTEDUSD" end)
    end

    test "returns exactly the two online entries for the fixture" do
      assert length(Products.parse_products(@fixture)) == 2
    end

    test "returns an empty list for a response with no products" do
      assert Products.parse_products(%{"has_next" => false}) == []
    end

    test "returns an empty list for a malformed/unexpected response shape" do
      assert Products.parse_products(%{}) == []
    end

    test "skips entries missing required fields instead of raising" do
      malformed = %{
        "products" => [
          %{"product_id" => "BAD-USD", "status" => "online"},
          hd(tl(@fixture["products"]))
        ]
      }

      assert [{"ETHUSD", "ETH-USD", _info}] = Products.parse_products(malformed)
    end
  end

  describe "cached lookups (to_product_id/1, to_concat/1, product_info/1)" do
    setup do
      # A lookup miss on an already-warm cache triggers exactly one refresh
      # attempt (in case the symbol was newly listed — see the moduledoc),
      # which would otherwise be a live network call to Coinbase's real API.
      # Point base_url at an unroutable loopback port instead: the HTTP GET
      # fails instantly with `econnrefused` (no packet ever reaches a real
      # host), `refresh/1` logs a warning and leaves the cache untouched,
      # and the lookup correctly falls through to `{:error, :unknown_symbol}`
      # — deterministic, network-free, no live Coinbase call involved.
      original = Application.get_env(:data_collector, :coinbase, [])

      Application.put_env(
        :data_collector,
        :coinbase,
        Keyword.put(original, :base_url, "http://127.0.0.1:1")
      )

      on_exit(fn -> Application.put_env(:data_collector, :coinbase, original) end)

      # DataCollector.Coinbase.Products is supervised by
      # DataCollector.Application (same as DataCollector.OKX.Symbols), so
      # it's already running by the time the test suite boots — no
      # start_supervised! here (that would conflict with the
      # already-registered name).
      @fixture
      |> Products.parse_products()
      |> Enum.each(&Products.cache_entry/1)

      # Mark the cache as already warm so lookups for symbols present in
      # the fixture resolve straight from ETS without any refresh attempt.
      :sys.replace_state(DataCollector.Coinbase.Products, fn state -> %{state | loaded?: true} end)

      :ok
    end

    test "to_product_id/1 resolves concat -> product_id" do
      assert Products.to_product_id("BTCUSD") == {:ok, "BTC-USD"}
      assert Products.to_product_id("ETHUSD") == {:ok, "ETH-USD"}
    end

    test "to_concat/1 resolves product_id -> concat" do
      assert Products.to_concat("BTC-USD") == {:ok, "BTCUSD"}
      assert Products.to_concat("ETH-USD") == {:ok, "ETHUSD"}
    end

    test "product_info/1 resolves concat -> base_increment/quote_increment/base_min_size" do
      assert Products.product_info("BTCUSD") ==
               {:ok,
                %{
                  base_increment: "0.00000001",
                  quote_increment: "0.01",
                  base_min_size: "0.00000001"
                }}
    end

    test "returns {:error, :unknown_symbol} for an unlisted concat" do
      assert Products.to_product_id("XXXUSDT") == {:error, :unknown_symbol}
      assert Products.to_concat("XXX-USDT") == {:error, :unknown_symbol}
      assert Products.product_info("XXXUSDT") == {:error, :unknown_symbol}
    end
  end
end
