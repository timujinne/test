defmodule DataCollector.Kraken.AuthTest do
  use ExUnit.Case, async: true

  alias DataCollector.Kraken.Auth

  # Kraken's own official worked example from the `spot-rest-auth` guide,
  # independently recomputed in both Python and Elixir before being written
  # to docs/superpowers/notes/kraken-api-verified.md §1 — byte-for-byte
  # match. Fixed inputs, deterministic expected output, no network/creds.
  @secret "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg=="
  @urlpath "/0/private/AddOrder"
  @nonce "1616492376594"
  @postdata "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25"
  @expected_signature "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ=="

  describe "sign/4" do
    test "matches Kraken's own worked example byte-for-byte" do
      assert Auth.sign(@secret, @urlpath, @nonce, @postdata) == @expected_signature
    end

    test "is deterministic for identical inputs" do
      sig1 = Auth.sign(@secret, @urlpath, @nonce, @postdata)
      sig2 = Auth.sign(@secret, @urlpath, @nonce, @postdata)

      assert sig1 == sig2
    end

    test "changes when any input changes" do
      base = Auth.sign(@secret, @urlpath, @nonce, @postdata)

      different_path = Auth.sign(@secret, "/0/private/CancelOrder", @nonce, @postdata)
      different_nonce = Auth.sign(@secret, @urlpath, "1616492376595", @postdata)
      different_postdata = Auth.sign(@secret, @urlpath, @nonce, @postdata <> "0")

      assert base != different_path
      assert base != different_nonce
      assert base != different_postdata
    end
  end

  describe "next_nonce/0" do
    test "returns strictly increasing decimal-digit strings" do
      first = Auth.next_nonce()
      second = Auth.next_nonce()

      assert first =~ ~r/^\d+$/
      assert second =~ ~r/^\d+$/
      assert String.to_integer(second) > String.to_integer(first)
    end
  end

  describe "headers/3" do
    @credentials %{api_key: "key123", secret_key: @secret, passphrase: nil}

    test "builds API-Key, API-Sign, and Content-Type headers" do
      headers = Auth.headers(@credentials, @urlpath, @postdata)
      map = Map.new(headers)

      assert map["API-Key"] == "key123"
      assert map["API-Sign"] == @expected_signature
      assert map["Content-Type"] == "application/x-www-form-urlencoded"
    end

    test "never includes a passphrase key" do
      headers = Auth.headers(@credentials, @urlpath, @postdata)
      keys = Enum.map(headers, fn {k, _v} -> k end)

      refute Enum.any?(keys, &(String.downcase(&1) =~ "passphrase"))
    end

    test "API-Sign matches sign/4 for the nonce embedded in postdata" do
      headers = Auth.headers(@credentials, @urlpath, @postdata)
      map = Map.new(headers)

      expected = Auth.sign(@secret, @urlpath, @nonce, @postdata)
      assert map["API-Sign"] == expected
    end
  end
end
