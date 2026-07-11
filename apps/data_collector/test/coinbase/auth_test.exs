defmodule DataCollector.Coinbase.AuthTest do
  # async: true — no shared/global state touched (no Application env
  # mutation, no ETS, no network); every check is a pure JOSE round-trip
  # against locally-generated or fixture (non-real) keys.
  use ExUnit.Case, async: true

  alias DataCollector.Coinbase.Auth

  @key_name "organizations/11111111-2222-3333-4444-555555555555/apiKeys/66666666-7777-8888-9999-000000000000"

  # The exact fake SEC1 EC PEM from
  # docs/superpowers/notes/coinbase-api-verified.md §1 "Check 2" — generated
  # purely for scouting via `openssl ecparam -genkey -name prime256v1
  # -noout`, never a live credential.
  @fixture_sec1_pem """
  -----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIHRlG6ROfo8brJ1ZJ+rwscLL2UZntIk8uJrNCfBf1pGioAoGCCqGSM49
  AwEHoUQDQgAEu6U9Z8Vk9Y+Vm1Je+fBzjA8YUlVai0Ekjgiy5/jcybckOHIgU3+G
  wV/PTLgODhsCVcdMHM5GwZjlnfQYwbgdmw==
  -----END EC PRIVATE KEY-----
  """

  describe "build_jwt/3" do
    test "produces a JWT that verifies against the matching public key, with a freshly generated P-256 key" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)

      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_jwt(credentials, "post", "/api/v3/brokerage/orders")

      {verified?, _payload, _jws} = JOSE.JWT.verify(JOSE.JWK.to_public(jwk), compact_jwt)
      assert verified?
    end

    test "header contains alg/typ/kid/nonce exactly as specified" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_jwt(credentials, "POST", "/api/v3/brokerage/orders")

      header = compact_jwt |> JOSE.JWS.peek_protected() |> Jason.decode!()

      assert header["alg"] == "ES256"
      assert header["typ"] == "JWT"
      assert header["kid"] == @key_name
      assert is_binary(header["nonce"])
      assert header["nonce"] != ""
    end

    test "claims contain sub/iss/nbf/exp(+120s)/uri exactly, and no aud claim" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      before = System.system_time(:second)
      compact_jwt = Auth.build_jwt(credentials, "POST", "/api/v3/brokerage/orders")
      claims = decode_payload(compact_jwt)

      assert claims["sub"] == @key_name
      assert claims["iss"] == "cdp"
      assert claims["nbf"] >= before
      assert claims["exp"] == claims["nbf"] + 120
      assert claims["uri"] == "POST api.coinbase.com/api/v3/brokerage/orders"
      refute Map.has_key?(claims, "aud")
    end

    test "uppercases the method in the uri claim" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_jwt(credentials, "get", "/api/v3/brokerage/accounts")
      claims = decode_payload(compact_jwt)

      assert claims["uri"] == "GET api.coinbase.com/api/v3/brokerage/accounts"
    end

    test "loads Coinbase's exact SEC1 PEM shape with zero conversion (fixture key)" do
      credentials = %{api_key: "test-key-id", secret_key: @fixture_sec1_pem, passphrase: nil}

      compact_jwt = Auth.build_jwt(credentials, "GET", "/api/v3/brokerage/accounts")

      jwk = JOSE.JWK.from_pem(@fixture_sec1_pem)
      {verified?, _payload, _jws} = JOSE.JWT.verify(JOSE.JWK.to_public(jwk), compact_jwt)
      assert verified?

      claims = decode_payload(compact_jwt)
      assert claims["sub"] == "test-key-id"
      assert claims["uri"] == "GET api.coinbase.com/api/v3/brokerage/accounts"
    end
  end

  describe "build_ws_jwt/1" do
    test "produces a JWT that verifies against the matching public key" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_ws_jwt(credentials)

      {verified?, _payload, _jws} = JOSE.JWT.verify(JOSE.JWK.to_public(jwk), compact_jwt)
      assert verified?
    end

    test "omits the uri claim entirely (not an empty string)" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_ws_jwt(credentials)
      claims = decode_payload(compact_jwt)

      refute Map.has_key?(claims, "uri")
    end

    test "claims otherwise match build_jwt/3's shape (sub/iss/nbf/exp, no aud)" do
      jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
      {_, pem} = JOSE.JWK.to_pem(jwk)
      credentials = %{api_key: @key_name, secret_key: pem, passphrase: nil}

      compact_jwt = Auth.build_ws_jwt(credentials)
      claims = decode_payload(compact_jwt)

      assert claims["sub"] == @key_name
      assert claims["iss"] == "cdp"
      assert claims["exp"] == claims["nbf"] + 120
      refute Map.has_key?(claims, "aud")
    end
  end

  defp decode_payload(compact_jwt) do
    %JOSE.JWT{fields: payload} = JOSE.JWT.peek_payload(compact_jwt)
    payload
  end
end
