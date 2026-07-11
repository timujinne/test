defmodule DataCollector.Coinbase.Auth do
  @moduledoc """
  Coinbase Advanced Trade CDP API key auth: ES256 JWT construction (see
  `docs/superpowers/notes/coinbase-api-verified.md` §1).

  Unlike Kraken (HMAC-SHA512 over a request path + body) or OKX (HMAC-SHA256
  over a timestamp/method/path/body prehash), Coinbase's CDP keys sign a
  short-lived (2-minute) **JWT** per request, built from an EC private key
  (SEC1 PEM, `-----BEGIN EC PRIVATE KEY-----`) via `JOSE`.

  Credential shape (`DataCollector.ExchangeClient.credentials/0`) note:
  `credentials.api_key` holds Coinbase's **key name**
  (`organizations/{org_id}/apiKeys/{key_id}`, used as both the JWT `kid`
  header and `sub` claim — not a secret, but not logged either out of
  general caution) and `credentials.secret_key` holds the **EC private key
  PEM** itself. `credentials.passphrase` is always `nil` for Coinbase.

  `build_jwt/3` is used for REST calls (`Authorization: Bearer <jwt>`,
  minted fresh per call — every REST call already gets its own JWT
  naturally). `build_ws_jwt/1` is used for WebSocket `subscribe` frames and
  must be minted fresh for **every** message sent, never cached/reused
  across sends or across reconnects — the JWT's 2-minute `exp` is per
  message, not per connection (verified notes §4).

  No `aud` claim is included in either — cross-checked against the official
  `coinbase-advanced-py` SDK source (higher-confidence than a generic docs
  page that claimed otherwise), see verified notes §1.
  """

  alias DataCollector.ExchangeClient

  @jwt_ttl_seconds 120

  @doc """
  Builds a REST-call JWT: `Authorization: Bearer <jwt>` header value (the
  `"Bearer "` prefix is added by the caller, not here).

  `method` is upcased automatically; `path` must include the leading `/`
  (e.g. `"/api/v3/brokerage/orders"`).
  """
  @spec build_jwt(ExchangeClient.credentials(), method :: String.t(), path :: String.t()) ::
          String.t()
  def build_jwt(%{api_key: key_name, secret_key: pem}, method, path)
      when is_binary(key_name) and is_binary(pem) and is_binary(method) and is_binary(path) do
    claims =
      base_claims(key_name)
      |> Map.put("uri", "#{String.upcase(method)} api.coinbase.com#{path}")

    sign(key_name, pem, claims)
  end

  @doc """
  Builds a WebSocket-`subscribe`-frame JWT: identical to `build_jwt/3` but
  with **no `uri` claim at all** (omitted entirely, not sent as an empty
  string — verified notes §1/§4).
  """
  @spec build_ws_jwt(ExchangeClient.credentials()) :: String.t()
  def build_ws_jwt(%{api_key: key_name, secret_key: pem})
      when is_binary(key_name) and is_binary(pem) do
    sign(key_name, pem, base_claims(key_name))
  end

  defp base_claims(key_name) do
    now = System.system_time(:second)

    %{
      "sub" => key_name,
      "iss" => "cdp",
      "nbf" => now,
      "exp" => now + @jwt_ttl_seconds
    }
  end

  defp sign(key_name, pem, claims) do
    jwk = JOSE.JWK.from_pem(pem)
    header = %{"alg" => "ES256", "typ" => "JWT", "kid" => key_name, "nonce" => random_nonce()}

    {_, compact} = JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact()
    compact
  end

  defp random_nonce, do: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
end
