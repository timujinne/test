defmodule DataCollector.OKX.Auth do
  @moduledoc """
  OKX v5 REST authentication: the `OK-ACCESS-*` request signature and header
  set (see `docs/superpowers/notes/okx-api-verified.md` §2).

  Signature recipe:

      prehash   = timestamp <> method <> request_path <> body
      signature = Base.encode64(:crypto.mac(:hmac, :sha256, secret_key, prehash))

  - `method` must be uppercase (`"GET"`, `"POST"`).
  - `request_path` includes the query string for GET requests (query params
    are part of the signed path, not signed separately).
  - `body` is the raw JSON request body string for POST, or the empty
    string `""` for GET (never `nil`).
  - `timestamp` is ISO-8601 UTC with millisecond precision, e.g.
    `"2020-12-08T09:08:57.715Z"`.
  """

  alias DataCollector.ExchangeClient

  @doc """
  Builds the Base64 HMAC-SHA256 `OK-ACCESS-SIGN` value.

  ## Examples

      iex> DataCollector.OKX.Auth.sign(
      ...>   "E65DA57D2BCC0C8D1B5E5D8B6C5B0F0A9C1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A",
      ...>   "2026-07-09T12:00:00.000Z",
      ...>   "GET",
      ...>   "/api/v5/account/balance?ccy=BTC",
      ...>   ""
      ...> )
      "Zdq/DiYil01hcLZ3qpwqqle6WfixpKpL0P+fW3LBtLo="
  """
  @spec sign(String.t(), String.t(), String.t(), String.t(), String.t()) :: String.t()
  def sign(secret_key, timestamp, method, request_path, body)
      when is_binary(secret_key) and is_binary(timestamp) and is_binary(method) and
             is_binary(request_path) and is_binary(body) do
    prehash = timestamp <> method <> request_path <> body

    :crypto.mac(:hmac, :sha256, secret_key, prehash)
    |> Base.encode64()
  end

  @doc """
  Current UTC timestamp in the ISO-8601 millisecond format OKX's REST
  `OK-ACCESS-TIMESTAMP` header requires (e.g. `"2020-12-08T09:08:57.715Z"`).

  Not used for the WebSocket login op, which requires unix-epoch-seconds
  instead — see `DataCollector.OKXPrivateStream`.
  """
  @spec timestamp() :: String.t()
  def timestamp do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  @doc """
  Builds the full private-REST-call header list: the 4 `OK-ACCESS-*`
  headers, `Content-Type`, and — only when `config :data_collector, :okx,
  demo: true` — `x-simulated-trading: 1`.

  `credentials.passphrase` is required (OKX rejects private calls without
  one); raises `ArgumentError` if it's missing so a misconfigured OKX
  account (e.g. one created before Task 1's passphrase column, or with a
  blank passphrase) fails loudly instead of silently sending a malformed
  request that OKX would reject anyway.
  """
  @spec headers(ExchangeClient.credentials(), String.t(), String.t(), String.t()) ::
          [{String.t(), String.t()}]
  def headers(credentials, method, request_path, body)

  def headers(%{passphrase: passphrase}, _method, _request_path, _body)
      when passphrase in [nil, ""] do
    raise ArgumentError, "OKX private API calls require a passphrase"
  end

  def headers(
        %{api_key: api_key, secret_key: secret_key, passphrase: passphrase},
        method,
        request_path,
        body
      ) do
    ts = timestamp()
    sig = sign(secret_key, ts, method, request_path, body)

    [
      {"OK-ACCESS-KEY", api_key},
      {"OK-ACCESS-SIGN", sig},
      {"OK-ACCESS-TIMESTAMP", ts},
      {"OK-ACCESS-PASSPHRASE", passphrase},
      {"Content-Type", "application/json"}
    ] ++ demo_header()
  end

  @doc """
  `[{"x-simulated-trading", "1"}]` when `config :data_collector, :okx,
  demo: true`, else `[]`. Exposed separately because `DataCollector.OKX.Symbols`
  also needs it for its (public, unauthenticated) instrument fetch.
  """
  @spec demo_header() :: [{String.t(), String.t()}]
  def demo_header do
    config = Application.get_env(:data_collector, :okx, [])

    if Keyword.get(config, :demo, false) do
      [{"x-simulated-trading", "1"}]
    else
      []
    end
  end
end
