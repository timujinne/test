defmodule DataCollector.Kraken.Auth do
  @moduledoc """
  Kraken Spot REST authentication: the `API-Key`/`API-Sign` header pair and
  the HMAC-SHA512 signature recipe behind `API-Sign` (see
  `docs/superpowers/notes/kraken-api-verified.md` §1).

  Signature recipe (Kraken's own one-line summary): *"HMAC-SHA512 of (URI
  path + SHA256(nonce + POST data)) and base64 decoded secret API key"*.

      secret_key = Base.decode64!(secret_b64)
      message    = urlpath <> :crypto.hash(:sha256, nonce <> postdata)
      signature  = :crypto.mac(:hmac, :sha512, secret_key, message) |> Base.encode64()

  Unlike OKX (which signs headers/timestamp/method/path/body separately),
  Kraken's `nonce` is intentionally concatenated **twice**: once raw ahead
  of `postdata`, and again as the literal `nonce=<value>` field *inside*
  `postdata` itself (since `postdata` is the full form-urlencoded POST
  body, which always includes `nonce`). This is not a bug — see the
  verified notes for two independently-sourced confirmations.

  - `urlpath` is always `/0/private/<Method>` with **no query string** —
    private Kraken calls never use query params, everything (including
    `nonce`) goes in the POST body.
  - `postdata` is the exact form-urlencoded request body string (built
    once by the caller and reused for both signing and the actual HTTP
    POST body — see `DataCollector.KrakenClient`).
  - Kraken has **no passphrase** concept (unlike OKX) — `headers/3` never
    touches `credentials.passphrase` and never raises on a missing one.
  """

  alias DataCollector.ExchangeClient

  @doc """
  Builds the Base64 HMAC-SHA512 `API-Sign` value.

  ## Examples

  Kraken's own official worked example (`spot-rest-auth` guide),
  independently recomputed in both Python and Elixir — byte-for-byte match:

      iex> DataCollector.Kraken.Auth.sign(
      ...>   "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg==",
      ...>   "/0/private/AddOrder",
      ...>   "1616492376594",
      ...>   "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25"
      ...> )
      "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ=="
  """
  @spec sign(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def sign(secret_b64, urlpath, nonce, postdata)
      when is_binary(secret_b64) and is_binary(urlpath) and is_binary(nonce) and
             is_binary(postdata) do
    secret_key = Base.decode64!(secret_b64)
    encoded = nonce <> postdata
    sha256_digest = :crypto.hash(:sha256, encoded)
    message = urlpath <> sha256_digest

    :crypto.mac(:hmac, :sha512, secret_key, message)
    |> Base.encode64()
  end

  @doc """
  The next value for the `nonce` POST body parameter — an "always
  increasing, unsigned 64-bit integer" per Kraken's own requirement, with
  "no way to reset ... to a lower value".

  Backed by a monotonic counter in the public named ETS table
  `:kraken_nonce` (created in `DataCollector.Application.start/2`).
  `:ets.update_counter/4`'s default-tuple form seeds the counter to the
  current epoch-ms on the very first call (so the first nonce this node
  ever produces is timestamp-shaped, same idiom Kraken's own suggested
  generation method uses) and every subsequent call is a plain atomic `+1`
  — race-safe across concurrent callers within the VM, never regresses
  even across a clock adjustment, and needs no per-call wall-clock
  comparison.
  """
  @spec next_nonce() :: String.t()
  def next_nonce do
    seed = System.system_time(:millisecond)

    :ets.update_counter(:kraken_nonce, :counter, {2, 1}, {:counter, seed})
    |> Integer.to_string()
  end

  @doc """
  Builds the private-REST-call header list: `API-Key`, `API-Sign`, and
  `Content-Type`. `postdata` is the exact already-built
  `nonce=...&...` form-urlencoded string that is also sent as the raw HTTP
  POST body — build it once and pass the same value here and to the HTTP
  call (see `DataCollector.KrakenClient`).

  Unlike `DataCollector.OKX.Auth.headers/4`, this never touches
  `credentials.passphrase` and never raises on a missing one — Kraken has
  no passphrase concept at all.
  """
  @spec headers(ExchangeClient.credentials(), String.t(), String.t()) ::
          [{String.t(), String.t()}]
  def headers(%{api_key: api_key, secret_key: secret_key}, urlpath, postdata)
      when is_binary(urlpath) and is_binary(postdata) do
    nonce = URI.decode_query(postdata)["nonce"]
    signature = sign(secret_key, urlpath, nonce, postdata)

    [
      {"API-Key", api_key},
      {"API-Sign", signature},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
  end
end
