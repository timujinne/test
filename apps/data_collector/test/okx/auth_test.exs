defmodule DataCollector.OKX.AuthTest do
  # async: false — the "omits x-simulated-trading when demo config is off"
  # test mutates the global `:data_collector, :okx` application env
  # (restored via on_exit/1); keeping this module synchronous avoids racing
  # other test modules that read the same config concurrently.
  use ExUnit.Case, async: false

  alias DataCollector.OKX.Auth

  # Worked examples from docs/superpowers/notes/okx-api-verified.md §2 and §9,
  # independently cross-checked in Python and Elixir before being written
  # down there. Fake secret, fixed inputs, deterministic expected output.
  @secret "E65DA57D2BCC0C8D1B5E5D8B6C5B0F0A9C1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A"

  describe "sign/5" do
    test "matches the POST worked example (trade/order, JSON body)" do
      timestamp = "2026-07-09T12:00:00.000Z"

      body =
        ~s({"instId":"BTC-USDT","tdMode":"cash","side":"buy","ordType":"market","sz":"10","tgtCcy":"quote_ccy"})

      assert Auth.sign(@secret, timestamp, "POST", "/api/v5/trade/order", body) ==
               "YPJab78iAPaVnK1BHTXlMCQ+4o/P4P/u3WoaAd4LtE4="
    end

    test "matches the GET worked example (account/balance, empty body)" do
      timestamp = "2026-07-09T12:00:00.000Z"

      assert Auth.sign(@secret, timestamp, "GET", "/api/v5/account/balance?ccy=BTC", "") ==
               "Zdq/DiYil01hcLZ3qpwqqle6WfixpKpL0P+fW3LBtLo="
    end

    test "matches the WS login worked example (fixed path, unix-seconds timestamp)" do
      assert Auth.sign(@secret, "1735732800", "GET", "/users/self/verify", "") ==
               "rlBIE2PpH+V+HkmlTkXQQ/eNuF5ULgE+P/5ggkT5W8U="
    end

    test "is deterministic for identical inputs" do
      sig1 = Auth.sign(@secret, "2026-07-09T12:00:00.000Z", "GET", "/api/v5/account/balance", "")
      sig2 = Auth.sign(@secret, "2026-07-09T12:00:00.000Z", "GET", "/api/v5/account/balance", "")

      assert sig1 == sig2
    end

    test "changes when any input changes" do
      base = Auth.sign(@secret, "2026-07-09T12:00:00.000Z", "GET", "/api/v5/account/balance", "")

      different_path =
        Auth.sign(@secret, "2026-07-09T12:00:00.000Z", "GET", "/api/v5/trade/order", "")

      different_secret =
        Auth.sign(
          "other_secret",
          "2026-07-09T12:00:00.000Z",
          "GET",
          "/api/v5/account/balance",
          ""
        )

      assert base != different_path
      assert base != different_secret
    end
  end

  describe "headers/4" do
    @credentials %{api_key: "key123", secret_key: @secret, passphrase: "pass123"}

    test "builds the 4 OK-ACCESS-* headers plus Content-Type" do
      headers = Auth.headers(@credentials, "GET", "/api/v5/account/balance", "")
      map = Map.new(headers)

      assert map["OK-ACCESS-KEY"] == "key123"
      assert map["OK-ACCESS-PASSPHRASE"] == "pass123"
      assert map["Content-Type"] == "application/json"
      assert is_binary(map["OK-ACCESS-TIMESTAMP"])
      assert is_binary(map["OK-ACCESS-SIGN"])
    end

    test "OK-ACCESS-SIGN matches sign/5 for the same timestamp" do
      headers = Auth.headers(@credentials, "POST", "/api/v5/trade/order", "{}")
      map = Map.new(headers)

      expected =
        Auth.sign(@secret, map["OK-ACCESS-TIMESTAMP"], "POST", "/api/v5/trade/order", "{}")

      assert map["OK-ACCESS-SIGN"] == expected
    end

    test "raises when passphrase is missing" do
      creds = %{api_key: "k", secret_key: "s", passphrase: nil}

      assert_raise ArgumentError, fn ->
        Auth.headers(creds, "GET", "/api/v5/account/balance", "")
      end
    end

    test "raises when passphrase is blank" do
      creds = %{api_key: "k", secret_key: "s", passphrase: ""}

      assert_raise ArgumentError, fn ->
        Auth.headers(creds, "GET", "/api/v5/account/balance", "")
      end
    end

    test "includes x-simulated-trading when demo config is on (test env default)" do
      # config/test.exs sets `demo: true` for :data_collector, :okx
      headers = Auth.headers(@credentials, "GET", "/api/v5/account/balance", "")
      map = Map.new(headers)

      assert map["x-simulated-trading"] == "1"
    end

    test "omits x-simulated-trading when demo config is off" do
      original = Application.get_env(:data_collector, :okx, [])
      Application.put_env(:data_collector, :okx, Keyword.put(original, :demo, false))

      on_exit(fn -> Application.put_env(:data_collector, :okx, original) end)

      headers = Auth.headers(@credentials, "GET", "/api/v5/account/balance", "")
      map = Map.new(headers)

      refute Map.has_key?(map, "x-simulated-trading")
    end
  end
end
