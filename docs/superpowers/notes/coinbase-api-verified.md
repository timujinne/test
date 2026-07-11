# Coinbase Advanced Trade API — Verified Facts (Task 0 scout)

Source of truth: `https://docs.cdp.coinbase.com` (official "Coinbase Developer Platform" docs,
a Mintlify-style client-rendered SPA — same genre of docs site as OKX's and Kraken's, and just as
unfriendly to `WebFetch`/`curl`). Fetched/cross-checked 2026-07-11.

**Method note (read this first, matches prior scouts' experience)**: `WebFetch` against
`docs.cdp.coinbase.com/**` pages returns a *summarized* window and is frequently wrong or empty —
several fetches against real, existing pages (confirmed by URL match in the page `<title>`) came
back "no information present" because the actual content is client-rendered via JS, not embedded
in the initial HTML the summarizer sees. `curl`-ing the raw HTML **did not help** here (unlike
Kraken's Mintlify site) — the page's own content isn't in a parseable embedded-JSON blob either;
only the *sidebar navigation* (real `<a href>` tags) is present in raw HTML, which was useful for
discovering correct canonical URLs but not for page content. Given this, every load-bearing fact
below was cross-checked using **one or more of**:
1. The **official `coinbase-advanced-py` SDK source code on GitHub**, fetched as raw file content
   (`raw.githubusercontent.com/...`) — this is Coinbase's own, actively-published, working
   reference implementation, and is treated as the single highest-confidence source in this
   document (equivalent to Kraken scout's "grep the raw HTML" trick, but even more reliable since
   it's executable ground truth, not prose).
2. **Live, unauthenticated, read-only or documented-no-auth-required calls** against
   `api.coinbase.com` (public market endpoints) and `api-sandbox.coinbase.com` (the whole sandbox
   requires no credentials per its own docs — see §5) — both safe per the "public/sandbox endpoints
   are fine to hit read-only" precedent set by the OKX/Kraken scouts, and in the sandbox's case
   explicitly *designed* to be probed without credentials.
3. An **independently-run Elixir round-trip** of the exact JOSE calls implementers would write,
   executed in this repo's own compiled `_build` (see §1) — the strongest possible confidence for
   the auth section, since it's not just "the docs say X" but "I built X in this exact stack and it
   verified successfully."
4. A second independent `WebSearch`/`WebFetch` pass for anything not covered by 1–3.

No live orders were placed against production Coinbase, and no real credentials exist for this
task. The one semi-live-write action taken was two `POST` calls to the **sandbox** `/orders`
endpoint, which is documented as requiring no auth and returning static/mocked data — see §5 for
why this was done and what it proved.

---

## 1. Auth: CDP API keys, ES256 JWT — ground truth from the official SDK

### Key types Coinbase issues

Per the official `coinbase-advanced-py` README (verbatim):

> Ed25519 is the recommended key type. The SDK also supports ECDSA for existing keys. The key type
> is auto-detected and the correct JWT signing algorithm (`EdDSA` or `ES256`) is selected
> automatically. Accepted formats:
> - **Ed25519** — PKCS8 PEM (`-----BEGIN PRIVATE KEY-----`), or raw base64 (32-byte seed or 64-byte
>   seed||pubkey as downloaded from the CDP portal)
> - **ECDSA** — SEC1 PEM (`-----BEGIN EC PRIVATE KEY-----`)

The plan's target is the **ECDSA / EC PEM** path (`-----BEGIN EC PRIVATE KEY-----`, SEC1 format,
P-256/secp256r1 curve) → **`ES256`**. The key id (`kid`)/`sub` value is the **full key name**
returned by the CDP portal, shaped `organizations/{org_id}/apiKeys/{key_id}` (a single opaque
string — not decomposed into separate org/key params anywhere in the JWT itself).

### JWT construction — verbatim from `coinbase/jwt_generator.py` (GitHub, `master`, fetched raw)

This is the **exact, complete, currently-published source** (not paraphrased):

```python
def _algorithm_for(private_key) -> str:
    if isinstance(private_key, ed25519.Ed25519PrivateKey):
        return "EdDSA"
    if isinstance(private_key, ec.EllipticCurvePrivateKey):
        return "ES256"
    raise ValueError(...)

def build_jwt(key_var, secret_var, uri=None) -> str:
    private_key = _load_private_key(secret_var)   # serialization.load_pem_private_key(...) for PEM

    jwt_data = {
        "sub": key_var,
        "iss": "cdp",
        "nbf": int(time.time()),
        "exp": int(time.time()) + 120,
    }
    if uri:
        jwt_data["uri"] = uri

    jwt_token = jwt.encode(
        jwt_data,
        private_key,
        algorithm=_algorithm_for(private_key),
        headers={"kid": key_var, "nonce": secrets.token_hex()},
    )
    return jwt_token

def format_jwt_uri(method, path) -> str:
    return f"{method} {BASE_URL}{path}"   # BASE_URL = "api.coinbase.com" (no scheme)
```

(`_load_private_key` accepts either a SEC1/PKCS8 PEM string — detected by `.lstrip().startswith("-----BEGIN")`
— or raw base64 for Ed25519; for our ECDSA/PEM case it's a straight
`serialization.load_pem_private_key(pem_bytes, password=None)` call.)

### Exact header + claims (implementers: build to this spec)

**Protected header** (all 4 fields; `typ` is added automatically by the JWT library used —
`pyjwt` on the Python side, confirmed our own `JOSE` does the same, see below — but it doesn't hurt
to set it explicitly):

| Header field | Value |
|---|---|
| `alg` | `"ES256"` (for our EC-key case; `"EdDSA"` for Ed25519 keys, not our target) |
| `typ` | `"JWT"` |
| `kid` | the full key name, `organizations/{org_id}/apiKeys/{key_id}` |
| `nonce` | random unique value per JWT — SDK uses `secrets.token_hex()` (64 hex chars, no fixed length mandated by docs, but match this convention) |

**Claims**:

| Claim | Value |
|---|---|
| `sub` | same key name as `kid` |
| `iss` | literal string `"cdp"` |
| `nbf` | current Unix time (seconds) |
| `exp` | `nbf + 120` (2 minutes — confirmed both in SDK source and in prose docs: *"Your JWT expires after 2 minutes, after which all requests are unauthenticated."*) |
| `uri` | **REST only** — `"{METHOD} {HOST}{PATH}"`, e.g. `"GET api.coinbase.com/api/v3/brokerage/accounts"` or `"POST api.coinbase.com/api/v3/brokerage/orders"`. Method is uppercase. There is a space between method and host, but **no separator between host and path** — the path already starts with `/`, so it reads as one contiguous `host+path` token after the space. **Omitted entirely for WebSocket JWTs** (`build_ws_jwt` calls `build_jwt` with no `uri` arg). |

**No `aud` claim** appears anywhere in the official SDK's JWT-building code. ⚠️ **Ambiguity flag**:
an earlier `WebSearch`-summarized pass over a different/generic CDP auth doc page claimed the
payload should include `"aud": ["cdp_service"]`. I could not confirm that in the ground-truth SDK
source for Advanced Trade specifically, and given the SDK is Coinbase's own actively-maintained,
working client for exactly this API, **I'm treating "no `aud` claim" as the correct, higher-confidence
answer for Advanced Trade** and flagging the `aud`-claim variant as likely belonging to a different/newer
generic CDP product surface (e.g. Wallet API v2) that shares the same JWT auth *style* but not
necessarily the identical claim set. Recommend implementers omit `aud` (matches the SDK); if a live
smoke test against real Advanced Trade credentials ever gets 401'd, adding
`"aud" => ["cdp_service"]` is the first thing to try.

### `Authorization` header

`Authorization: Bearer <jwt>` — standard bearer token, on every REST call (private *and*, per the
sandbox findings in §5, technically optional against the sandbox host).

### Worked example — built and round-tripped in THIS repo's own Elixir/JOSE, live

Ran directly against `_build/test/lib/jose/ebin` in this worktree (no `mix deps.get`, no lockfile
touched — `jose` is already compiled because it's a transitive dep via `ueberauth_apple`). Two
separate checks, both passed:

**Check 1 — generate a P-256 key via `JOSE.JWK.generate_key/1`, round-trip through PEM:**
```elixir
jwk = JOSE.JWK.generate_key({:ec, :secp256r1})
{_, pem} = JOSE.JWK.to_pem(jwk)
loaded_jwk = JOSE.JWK.from_pem(pem)

key_name = "organizations/11111111-2222-3333-4444-555555555555/apiKeys/66666666-7777-8888-9999-000000000000"
nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
now = System.system_time(:second)

claims = %{
  "sub" => key_name, "iss" => "cdp",
  "nbf" => now, "exp" => now + 120,
  "uri" => "POST api.coinbase.com/api/v3/brokerage/orders"
}
header = %{"alg" => "ES256", "typ" => "JWT", "kid" => key_name, "nonce" => nonce}

{_, compact_jwt} = JOSE.JWT.sign(loaded_jwk, header, claims) |> JOSE.JWS.compact()
{verified?, verified_payload, _jws} = JOSE.JWT.verify(JOSE.JWK.to_public(loaded_jwk), compact_jwt)
```
Result: `verified? == true`, decoded protected header exactly
`{"alg":"ES256","kid":"organizations/...","nonce":"...","typ":"JWT"}`, decoded payload exactly the
claims map above (byte-for-byte, all 5 fields present, nothing extra).

**Check 2 — the format Coinbase actually issues (`openssl ecparam` → SEC1 `-----BEGIN EC PRIVATE
KEY-----`, i.e. the exact PEM shape from the CDP portal, not JOSE's own PKCS8-by-default output):**
```
$ openssl ecparam -genkey -name prime256v1 -noout -out /tmp/sec1_test_key.pem
$ cat /tmp/sec1_test_key.pem
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIHRlG6ROfo8brJ1ZJ+rwscLL2UZntIk8uJrNCfBf1pGioAoGCCqGSM49
AwEHoUQDQgAEu6U9Z8Vk9Y+Vm1Je+fBzjA8YUlVai0Ekjgiy5/jcybckOHIgU3+G
wV/PTLgODhsCVcdMHM5GwZjlnfQYwbgdmw==
-----END EC PRIVATE KEY-----
```
```elixir
pem = File.read!("/tmp/sec1_test_key.pem")
jwk = JOSE.JWK.from_pem(pem)          # loads fine — SEC1 EC PEM is supported directly
header = %{"alg" => "ES256", "typ" => "JWT", "kid" => "test-key-id", "nonce" => "abc123"}
claims = %{"sub" => "test-key-id", "iss" => "cdp", "nbf" => 1000, "exp" => 1120,
           "uri" => "GET api.coinbase.com/api/v3/brokerage/accounts"}
{_, compact_jwt} = JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact()
{verified?, _, _} = JOSE.JWT.verify(JOSE.JWK.to_public(jwk), compact_jwt)
```
Result: `verified? == true`. **This confirms `JOSE.JWK.from_pem/1` loads Coinbase's exact SEC1 PEM
format with zero conversion needed**, and the sign→compact→verify round-trip works end to end.

**Check 3 (side finding)** — omitting `"typ"` from the header map entirely still produces
`"typ":"JWT"` in the output; `JOSE`, like `pyjwt`, injects it automatically. Safe either way; being
explicit costs nothing.

### `jose` version — confirmed compatible, mix.lock untouched

`mix.lock` in this worktree already pins:
```
"jose": {:hex, :jose, "1.11.12", ...}
```
(pulled in transitively via `ueberauth_apple`, itself requiring `{:jose, "~> 1.0", ...}`). It's
already compiled in `_build/{dev,test}/lib/jose`. `JOSE.JWS`'s own moduledoc explicitly lists
`"ES256"` as a supported algorithm (alongside ES384/ES512/EdDSA/HS*/RS*/PS*), and
`JOSE.JWK.from_pem/1`, `JOSE.JWK.from_pem_file/1` exist and — per Check 2 above — handle SEC1 EC
PEM directly.

**Recommendation for `apps/data_collector/mix.exs`**: add `{:jose, "~> 1.11"}` to `deps()`. Since
`"~> 1.11"` means `>= 1.11.0 and < 1.12.0`, and the umbrella-wide lock already resolves `jose` to
exactly `1.11.12` (which satisfies that range), Mix's resolver has nothing to change — the
already-locked version is reused as-is. **I did not run `mix deps.get`** (per the env rules); this
conclusion is a straightforward semver-compatibility read of the existing `mix.lock` line, not a
live-verified deps.get run — flag for the implementer to eyeball `mix.lock` after adding the dep
declaration and confirm it's still byte-identical (`git diff mix.lock` should be empty).

### Recommended Elixir shape for implementers (not yet written, just the recipe this scout verified)

```elixir
jwk = JOSE.JWK.from_pem(ec_private_key_pem)   # the "-----BEGIN EC PRIVATE KEY-----" string as-is
header = %{"alg" => "ES256", "typ" => "JWT", "kid" => key_name, "nonce" => random_hex()}
claims = %{"sub" => key_name, "iss" => "cdp", "nbf" => now, "exp" => now + 120, "uri" => "#{method} api.coinbase.com#{path}"}
{_, compact_jwt} = JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact()
# Authorization: "Bearer " <> compact_jwt
```
A pure "claims + header correctly built" unit test (per the task's ask) can assert on the decoded
header/payload maps exactly as shown in Check 1/2 above, and can additionally do a full
`JOSE.JWT.verify(public_jwk, compact_jwt)` round-trip using a **locally-generated fake test key**
(never a real credential) — exactly the pattern demonstrated above.

---

## 2. REST base + endpoints

**Base URL**: `https://api.coinbase.com`. **API prefix**: `/api/v3/brokerage`. Full paths below are
relative to the base (prefix included in each path shown). Confirmed via SDK's `constants.py`
(`BASE_URL = "api.coinbase.com"`, `API_PREFIX = "/api/v3/brokerage"`) and live `curl` calls.

### Create Order — `POST /api/v3/brokerage/orders`

Required body: `client_order_id` (string — **reusing a non-unique id returns the existing order
instead of erroring**, per docs; empty string auto-generates one but forfeits the
duplicate-order safeguard), `product_id`, `side` (`BUY`|`SELL`), `order_configuration` (object).

**`order_configuration` variants relevant to this plan** (there are 12 total; only these 2 are
needed):

- **`market_market_ioc`**: `base_size` OR `quote_size` (exactly one; string), optional
  `rfq_disabled` (bool).
- **`limit_limit_gtc`**: `base_size` OR `quote_size` (string), `limit_price` (string, required),
  `post_only` (bool, default `false`), optional `rfq_disabled`.

Example request (docs' own):
```json
{
  "client_order_id": "0000-00000-000000",
  "product_id": "BTC-USD",
  "side": "BUY",
  "order_configuration": {
    "limit_limit_gtc": { "base_size": "0.001", "limit_price": "10000.00", "post_only": false }
  }
}
```

Success response:
```json
{
  "success": true,
  "success_response": {
    "order_id": "11111-00000-000000",
    "product_id": "BTC-USD",
    "side": "BUY",
    "client_order_id": "0000-00000-000000"
  },
  "order_configuration": { "limit_limit_gtc": { "base_size": "0.001", "limit_price": "10000.00", "post_only": false } }
}
```
Note: **response does NOT include price/qty/status directly on `success_response`** — only
`order_id`/`product_id`/`side`/`client_order_id`. To build the Binance-shaped order map (with
`"price"`, `"origQty"`, `"status"`, etc.) you need a **follow-up `GET` order-details call** (below)
— same pattern the OKX adapter already uses ("GET the order after placing").

Error response (HTTP 200 with `success: false`, **not necessarily a 4xx/5xx** — check `success`,
don't rely on status code alone):
```json
{
  "success": false,
  "error_response": {
    "error": "UNSUPPORTED_ORDER_CONFIGURATION",
    "message": "The order configuration was invalid",
    "error_details": "Market orders cannot be placed with empty order sizes",
    "new_order_failure_reason": "UNSUPPORTED_ORDER_CONFIGURATION"
  }
}
```
`new_order_failure_reason` is the current field to branch on (`error` is documented **deprecated**).
Common values seen in the enum: `UNKNOWN_FAILURE_REASON`, `INVALID_PRODUCT_ID`, `INSUFFICIENT_FUND`,
`INVALID_SIZE_PRECISION`, `INVALID_LIMIT_PRICE`, `ORDER_ENTRY_DISABLED`, `INELIGIBLE_PAIR`,
`UNTRADABLE_PRODUCT`, `GEOFENCING_RESTRICTION`, `DUPLICATE_CLIENT_ORDER_ID` (100+ total values per
docs; these are the ones most likely to matter to this app).

### Get Order — `GET /api/v3/brokerage/orders/historical/{order_id}`

Response includes: `order_id`, `client_order_id`, `status` (see §2.5 for enum), `order_type`,
`side`, `filled_size` (string, base-currency), `average_filled_price` (string),
`completion_percentage` (string, e.g. `"50"`), `order_configuration` (echo), `created_time`
(RFC3339). This is the endpoint implementers use post-Create-Order to build the Binance-shaped
order map (`"price"` ← `limit_price` from the echoed `order_configuration`, or `average_filled_price`
for a filled market order; `"origQty"` ← the `base_size`/`quote_size` from the echoed config;
`"executedQty"` ← `filled_size`).

### List Orders (open orders) — `GET /api/v3/brokerage/orders/historical/batch`

Query params: `order_status` (array — e.g. `["OPEN"]` to scope to open orders, matching this app's
`orders-pending`-equivalent need), `product_id` (array, optional filter), `order_type`,
`order_side`, `limit`, `cursor`. Full `order_status` enum: `PENDING`, `OPEN`, `FILLED`,
`CANCELLED` **(double-L — see §2.5)**, `EXPIRED`, `FAILED`, `UNKNOWN_ORDER_STATUS`, `QUEUED`,
`CANCEL_QUEUED`, `EDIT_QUEUED`.

```json
{
  "orders": [ { "order_id": "...", "client_order_id": "...", "product_id": "...", "side": "BUY",
                "status": "OPEN", "order_type": "LIMIT", "filled_size": "...",
                "average_filled_price": "...", "created_time": "...", "completion_percentage": "..." } ],
  "has_next": false, "cursor": ""
}
```

### Cancel Orders (batch) — `POST /api/v3/brokerage/orders/batch_cancel`

Confirmed path via cross-referenced search + docs page (the docs site's own internal linking uses
inconsistent slugs — `.../orders/cancel-order` in the URL but the endpoint itself is the
batch-shaped `/orders/batch_cancel`; don't be misled by the doc-page slug). Max 100 `order_ids` per
request (docs: exceeding it returns an `InvalidArgument` error).

Request:
```json
{ "order_ids": ["0000-00000", "1111-11111"] }
```
Response:
```json
{ "results": [ { "success": true, "failure_reason": "UNKNOWN_CANCEL_FAILURE_REASON", "order_id": "0000-00000" } ] }
```
Per-order result, not an all-or-nothing batch — always inspect each `results[]` entry.
`failure_reason` enum includes `DUPLICATE_CANCEL_REQUEST`, `ORDER_IS_FULLY_FILLED` (i.e. too-late-to-cancel),
`NOT_ALLOWED_TO_CANCEL`.

### Accounts (balances) — `GET /api/v3/brokerage/accounts`

Query: `limit` (default ~49, max 250), `cursor` (pagination). Response:
```json
{ "accounts": [ { "uuid": "...", "currency": "BTC",
                   "available_balance": { "value": "1.2435", "currency": "BTC" },
                   "hold": { "value": "0.8423", "currency": "BTC" },
                   "type": "ACCOUNT_TYPE_CRYPTO", "active": true, "ready": true, ... } ],
  "has_next": false, "cursor": "", "size": 4 }
```
Live-confirmed exact shape via the sandbox (§5) — this is a **real observed response**, not just
docs prose:
```json
{"uuid":"66f975a6-bb2e-44be-82e9-cd8669e404b0","name":"USDC Wallet","currency":"USDC",
 "available_balance":{"value":"100","currency":"USDC"},"default":true,"active":true,
 "created_at":"2023-12-14T21:40:32.181Z","updated_at":"2023-12-19T18:21:42.850Z","deleted_at":null,
 "type":"ACCOUNT_TYPE_CRYPTO","ready":true,"hold":{"value":"0","currency":"USDC"},
 "retail_portfolio_id":"1fb3c56a-489f-418c-8b5c-ce04268be5a6","platform":"ACCOUNT_PLATFORM_CONSUMER"}
```
**Mapping to Binance-shaped `%{"balances" => [%{"asset","free","locked"}]}`**: `"asset"` ←
`currency`, `"free"` ← `available_balance.value`, `"locked"` ← `hold.value`. No pagination gotcha
different from any other cursor-paginated endpoint in this app — loop on `has_next`/`cursor` if the
account has >250 non-zero-and-zero balances (in practice: every asset the account has ever touched
gets an account row, even zero-balance ones — expect to filter).

### Products (exchange info) — `GET /api/v3/brokerage/products` (list) and `GET /api/v3/brokerage/products/{product_id}` (single)

Query on list: `product_type` (`SPOT`|`FUTURE`|`UNKNOWN_PRODUCT_TYPE` — pass `SPOT`), `limit`,
`cursor`. **Live-verified full field set** for a single product (pulled from the live **public,
unauthenticated** `GET /api/v3/brokerage/market/products/{id}` mirror endpoint — see §3 for why the
`market/` prefix variant was used for the live pull instead of the authenticated one; field names
are identical):
```json
{
  "product_id": "BTC-USD", "base_currency_id": "BTC", "quote_currency_id": "USD",
  "base_increment": "0.00000001", "quote_increment": "0.01", "price_increment": "0.01",
  "base_min_size": "0.00000001", "base_max_size": "3400", "quote_min_size": "1", "quote_max_size": "150000000",
  "status": "online", "trading_disabled": false, "is_disabled": false, "cancel_only": false,
  "limit_only": false, "post_only": false, "product_type": "SPOT", "alias": "", "alias_to": ["BTC-USDC"],
  "price": "64110.6", "base_name": "Bitcoin", "quote_name": "US Dollar", ...
}
```
**Mapping to Binance-shaped `%{"symbols" => [%{"symbol","filters"}]}`**: `"symbol"` ← `product_id`
converted to concat form (strip the `-`, see §3), `PRICE_FILTER.tickSize` ← `quote_increment` (note
there's also a `price_increment` field carrying the identical value — legacy alias from the old
Coinbase Exchange/Pro API's field name, kept for backward compat; use `quote_increment` as primary,
they agreed in every live sample checked), `LOT_SIZE.stepSize` ← `base_increment`, `LOT_SIZE.minQty`
← `base_min_size`. **Only `status == "online"` products are tradable** — every live-pulled sample in
§3's 925-product dataset showed `status: "online"` exclusively (i.e. delisted/paused products
appear to simply not be returned by this endpoint rather than being returned with a non-`online`
status — could not find a live counter-example; treat `status != "online"` defensively as
non-tradable if ever encountered, but don't assume the enum's other values from docs prose alone,
they weren't independently confirmed).

Interesting live-only finding: `BTC-USD`'s `alias_to` is `["BTC-USDC"]` — Coinbase internally links
the USD and USDC order books for at least this pair (not something the plan needs to act on, but
worth knowing if fill prices ever look like they're coming from a shared book).

### Candles — `GET /api/v3/brokerage/products/{product_id}/candles`

Required query: `start`, `end` (both Unix-seconds strings), `granularity` — **enum of string
names, NOT a raw seconds integer** (unlike Binance's `interval` or OKX's `bar`): `ONE_MINUTE`,
`FIVE_MINUTE`, `FIFTEEN_MINUTE`, `THIRTY_MINUTE`, `ONE_HOUR`, `TWO_HOUR`, `FOUR_HOUR`, `SIX_HOUR`,
`ONE_DAY`. Live-confirmed via the **public** `GET /api/v3/brokerage/market/products/{id}/candles`
mirror (no auth needed for market data — see §3):
```json
{"candles":[{"start":"1783773180","low":"64094.01","high":"64105.52","open":"64105.52","close":"64096.22","volume":"2.07386523"}, ...]}
```
Rows are newest-first in the live response observed. Max 350 candles per docs prose (not
independently stress-tested).

### Preview Order — `POST /api/v3/brokerage/orders/preview`

Not in the original required-endpoint list but worth knowing it exists: dry-run order validation,
returns a `preview_id` plus computed totals/commission/warnings without placing anything. Could be
a useful non-order-placing smoke-test analog to Kraken's `validate=true` or OKX's demo-trading, but
**still requires real, authenticated production credentials** (unlike the sandbox) — same posture
as Kraken's `validate=true`, not usable from unit tests, only from a human-run E2E checklist.

### Generic error envelope

For non-order-specific failures (auth errors, malformed requests, etc.), docs reference a
`grpc.gateway.runtime.Error` schema: `{"error": "string", "code": <int32>, "message": "string",
"details": [...]}`. Not independently live-triggered (would require either bad credentials against
production or malformed sandbox calls); recorded from docs as the documented shape, flagged as
**docs-only, not live-confirmed**.

### Order status mapping — CONFIRMED enum, PARTIALLY_FILLED must be derived (same pattern as Kraken)

Full `status`/`order_status` enum (identical set appears in both List/Get Order REST responses and
is referenced consistently across docs): `PENDING`, `QUEUED`, `OPEN`, `CANCEL_QUEUED`,
`EDIT_QUEUED`, `FILLED`, `CANCELLED` **(spelled with double-L — British spelling; do NOT write
`CANCELED` when checking Coinbase's own field value, only in the app's own normalized output)**,
`EXPIRED`, `FAILED`, `UNKNOWN_ORDER_STATUS`.

**There is no separate `PARTIALLY_FILLED` value in this enum** — confirmed live via the sandbox's
own canned example order (`order_id: "c6981abf-..."`, `status: "OPEN"`, `completion_percentage:
"20"`, `filled_size: "0.01"` out of a larger order) — a partially-filled order is still
`status: "OPEN"`, just with `filled_size > 0` and `< order size`. Same REST-shows-fewer-buckets
pattern the Kraken scout found on `OpenOrders`.

Recommended normalization table:

| Coinbase `status` | Condition | Binance-shaped `status` |
|---|---|---|
| `PENDING`, `QUEUED` | — | `NEW` |
| `OPEN` | `filled_size == "0"` (or `completion_percentage == "0"`) | `NEW` |
| `OPEN` | `0 < filled_size < order size` | `PARTIALLY_FILLED` |
| `CANCEL_QUEUED`, `EDIT_QUEUED` | — | `NEW` (still resting; cancel/edit not yet finalized) |
| `FILLED` | — | `FILLED` |
| `CANCELLED` | — | `CANCELED` |
| `EXPIRED` | — | `CANCELED` (terminal-non-fill bucket, same fold used for OKX's `mmp_canceled` and Kraken's `expired`) |
| `FAILED` | — | `CANCELED` (never got resting — order-entry rejection) |
| `UNKNOWN_ORDER_STATUS` | — | fallback: log warning, pass through upcased, same convention as other adapters |

The WebSocket `user` channel's order events (§4) use the **same `status` enum values** (its own
canonical example shows `"status": "FILLED"`) but a **different field name for cumulative fill**
(`cumulative_quantity` instead of REST's `filled_size`) — flagged explicitly in §4 as an easy
cross-wiring mistake.

---

## 3. Products/symbols — the USDT question (live-verified, load-bearing finding)

### Format

`product_id` = `"{BASE}-{QUOTE}"`, hyphen-separated, e.g. `BTC-USD`, `BTC-USDT`, `BTC-EUR`. Mapping
recipe: concat (Binance-style) ↔ `product_id` is a straight `String.replace(product_id, "-", "")`
in one direction and inserting the hyphen at the base/quote boundary (known from the product's own
`base_currency_id`/`quote_currency_id` fields, or from a prebuilt lookup table — same
"build the table from a live product-list fetch, don't hardcode" recommendation as the Kraken
scout gave) in the other. **No legacy-ticker translation table needed** (unlike Kraken's XBT/XDG) —
Coinbase uses plain, current tickers throughout (`BTC`, not `XBT`).

### Does Coinbase actually have tradable USDT-quoted spot products? **Yes, but they are a small minority — and likely unusable from an EU-domiciled account. Read this before wiring `product_id` selection.**

Pulled **live**, fully paginated, from the **public, unauthenticated**
`GET https://api.coinbase.com/api/v3/brokerage/market/products?product_type=SPOT` endpoint (925
total SPOT products returned across the full paginated set, `curl`'d directly, not sourced from
docs prose):

| Quote currency | Count (of 925 SPOT products) |
|---|---|
| `USDC` | 410 |
| `USD` | 395 |
| `EUR` | 35 |
| `GBP` | 25 |
| `BTC` | 24 |
| **`USDT`** | **23** |
| `ETH` | 6 |
| `INR` | 4 |
| `SGD`, `CAD`, `AUD` | 1 each |

All 23 USDT-quoted pairs, live-confirmed `status: "online"`, `trading_disabled: false` at fetch
time: `BTC-USDT`, `SOL-USDT`, `ETH-USDT`, `ADA-USDT`, `HBAR-USDT`, `AVAX-USDT`, `NEAR-USDT`,
`XRP-USDT`, `DOGE-USDT`, `XLM-USDT`, `FET-USDT`, `OP-USDT`, `DOT-USDT`, `LINK-USDT`, `ATOM-USDT`,
`IMX-USDT`, `APE-USDT`, `STX-USDT`, `CHZ-USDT`, `QNT-USDT`, `JASMY-USDT`, `SHIB-USDT`, `CRO-USDT`.

**So: yes, USDT pairs technically exist and show as tradable in Coinbase's global product catalog**
— this app's `BTCUSDT`-style concat symbols *can* resolve to a real `product_id` (`BTC-USDT`) for
the 23 listed above. But two caveats make this a real engine-compatibility concern, not a clean
match:

1. **USDT is a tiny fraction of Coinbase's spot liquidity** — 23 pairs vs. 410 USDC-quoted + 395
   USD-quoted (a combined 87% of all SPOT products). Most assets this app might want to trade
   simply **have no USDT pair on Coinbase at all** and are only available USD- or USDC-quoted. Any
   symbol-resolution logic that assumes "just append USDT" (as this app's Binance-oriented strategy
   layer implicitly does via concat symbols) will fail to resolve for the vast majority of
   Coinbase's actual catalog.
2. **EU/EEA-domiciled accounts almost certainly cannot trade USDT on Coinbase at all, regardless of
   what the global product catalog shows.** Confirmed via independent web search (multiple
   corroborating sources, not just one): under the EU's MiCA regulation, Tether (USDT's issuer)
   did not seek MiCA authorization, and Coinbase **delisted USDT for EEA users** — announced 3 Dec
   2024, effective **31 March 2025**. EEA users can still hold/withdraw/transfer existing USDT, but
   **new USDT listings/trading are not offered to EEA retail/professional clients** on
   MiCA-authorized venues (which Coinbase's EU-facing entity is). This is a live regulatory fact,
   not a docs artifact — the public product-catalog endpoint I hit is **global** and does not
   reflect per-account/per-region eligibility, so it will happily show `BTC-USDT` as `online` even
   though an actual EU account attempting to trade it would very likely get a
   `GEOFENCING_RESTRICTION` or `INELIGIBLE_PAIR` `new_order_failure_reason` (see §2's error enum) —
   **this could not be directly live-tested** (no EU account/credentials available to this scout),
   so it's inference from the regulatory announcement + the documented failure-reason enum
   containing exactly this bucket, not a confirmed API response. Flagging as **high-confidence
   inference, not a live-verified fact**.

**Practical recommendation for implementers**: for a Coinbase adapter aimed at EU users (or any user
where USDT tradability isn't independently confirmed), **prefer `USD`- or `USDC`-quoted
`product_id`s over `USDT`-quoted ones** when resolving a Binance-style concat symbol, and treat
`XXXUSDT` → `XXX-USDT` resolution as best-effort/likely-to-fail rather than the primary path. This
is the single most important engine-compatibility caveat in this whole scouting pass — the app's
strategy layer's assumption of ubiquitous `BASEUSDT`-style symbols does not hold for Coinbase the
way it does for Binance/OKX, and holds even less for a plausible EU deployment target.

### Public vs. authenticated product/candle endpoints — a naming quirk worth knowing

Live testing revealed Coinbase exposes **two parallel path families** for read-only market data:
`GET /api/v3/brokerage/products...` (documented as requiring the standard JWT auth) and
`GET /api/v3/brokerage/market/products...` (the `market/`-prefixed **public** mirror, confirmed to
work with **zero auth headers** in this scout's live `curl` calls — used for all the live pulls in
this section). Response shapes are identical between the two families for the fields checked. Per
docs prose (not independently stress-tested): public endpoints have "1-second caching" — use
`Cache-Control: no-cache` or the WebSocket feed if fresher data is needed. Implementers building the
adapter's `get_exchange_info`/candles calls should decide deliberately whether to use the
authenticated or public path family — the public one avoids burning any private rate-limit budget
for pure market-data reads.

---

## 4. WebSocket (`advanced-trade`)

### URLs

| | URL |
|---|---|
| Market data (public channels: `ticker`, `level2`, `market_trades`, `candles`, `status`, `heartbeats`) | `wss://advanced-trade-ws.coinbase.com` |
| User order data (private: `user`, `futures_balance_summary`) | `wss://advanced-trade-ws-user.coinbase.com` |

Confirmed via the SDK's `constants.py` (`WS_BASE_URL`/`WS_USER_BASE_URL`) — ground truth, not docs
prose.

### Subscribe frame — JWT is a field IN the subscribe message, not a separate login step

Unlike OKX (separate `{"op":"login",...}` frame before subscribing) or Kraken (token obtained via a
prior REST call, passed in `params.token`), Coinbase puts the JWT **directly in the `subscribe`
message itself**:
```json
{ "type": "subscribe", "product_ids": ["ETH-USD", "ETH-EUR"], "channel": "level2", "jwt": "exampleJWT" }
```
For our channels:
```json
{ "type": "subscribe", "product_ids": ["BTC-USD"], "channel": "ticker", "jwt": "<jwt-optional-for-public-channel>" }
{ "type": "subscribe", "product_ids": ["BTC-USD"], "channel": "user", "jwt": "<jwt-required>" }
```
- `ticker` (public channel) does not strictly require `jwt` to be present/valid, but `user` (and
  `futures_balance_summary`) do — docs list `WS_AUTH_CHANNELS = {"user", "futures_balance_summary"}`
  in the SDK constants as exactly the channels needing auth.
- **Must subscribe within 5 seconds of connecting or the server disconnects you** — confirmed both
  in prose (*"you are disconnected if no `subscribe` has been received within 5 seconds"*) and is a
  harder deadline than OKX's ~30s idle-keepalive or Kraken's undocumented threshold.
- **A fresh JWT is needed for every WS message that requires auth**, not just the initial subscribe
  — because the JWT's `exp` is only 2 minutes out: *"you must generate a different JWT for each
  websocket message sent, since the JWTs will expire after 2 minutes."* This is stricter than REST
  (where each call naturally gets its own fresh JWT anyway) — for a long-lived WS connection,
  implementers need to mint a new JWT on every `subscribe`/`unsubscribe` call, not just once at
  connect time. No `uri` claim is included for WS JWTs (confirmed via `build_ws_jwt` calling
  `build_jwt` with no `uri` argument — see §1).

### Channel event examples — official canonical examples, full field lists

**`heartbeats`** (auto-flows once subscribed to keep the connection alive during quiet periods —
same purpose as OKX's ping/pong, but push-based rather than app-level-ping-based):
```json
{
  "channel": "heartbeats", "timestamp": "2023-06-23T20:31:26.122969572Z", "sequence_num": 0,
  "events": [ { "current_time": "2023-06-23 20:31:56.121961769 +0000 UTC m=+91717.525857105", "heartbeat_counter": 3049 } ]
}
```

**`ticker`** (public):
```json
{
  "channel": "ticker", "timestamp": "2023-02-09T20:30:37.167359596Z", "sequence_num": 0,
  "events": [ { "type": "snapshot", "tickers": [ {
    "type": "ticker", "product_id": "BTC-USD", "price": "21932.98",
    "volume_24_h": "16038.28770938", "low_24_h": "21835.29", "high_24_h": "23011.18",
    "low_52_w": "15460", "high_52_w": "48240", "price_percent_chg_24_h": "-4.15775596190603",
    "best_bid": "21931.98", "best_bid_quantity": "8000.21",
    "best_ask": "21933.98", "best_ask_quantity": "8038.07770938"
  } ] } ]
}
```
`type` is `"snapshot"` on first push, `"update"` thereafter (same convention as Kraken's WS v2).
For the Binance-shaped ticker map: `"c"` (last price) ← `events[].tickers[].price`; `"s"` ←
`product_id` with the `-` stripped via `Coinbase.Symbols.to_concat/1`. Note the **envelope is
nested two levels deep** (`data.events[].tickers[]`, not a flat `data[]` array like OKX/Kraken) —
the normalizer needs to flat-map over both `events` and `tickers` (there can be multiple product
tickers in one `events[].tickers[]` array if subscribed to multiple `product_ids`).

**`user`** (private, order updates) — official canonical example, full field list:
```json
{
  "channel": "user", "timestamp": "2023-02-09T20:33:57.609931463Z", "sequence_num": 0,
  "events": [ { "type": "snapshot", "orders": [ {
    "avg_price": "50000", "cancel_reason": "", "client_order_id": "XXX",
    "completion_percentage": "100.00", "contract_expiry_type": "UNKNOWN_CONTRACT_EXPIRY_TYPE",
    "cumulative_quantity": "0.01", "filled_value": "500", "leaves_quantity": "0",
    "limit_price": "50000", "number_of_fills": "1", "order_id": "YYY", "order_side": "BUY",
    "order_type": "Limit", "outstanding_hold_amount": "0", "post_only": "false",
    "product_id": "BTC-USD", "product_type": "SPOT", "reject_reason": "",
    "retail_portfolio_id": "ZZZ", "risk_managed_by": "UNKNOWN_RISK_MANAGEMENT_TYPE",
    "status": "FILLED", "stop_price": "", "time_in_force": "GOOD_UNTIL_CANCELLED",
    "total_fees": "2", "total_value_after_fees": "502", "trigger_status": "INVALID_ORDER_TYPE",
    "creation_time": "2024-06-21T18:29:13.909347Z",
    "end_time": "0001-01-01T00:00:00Z", "start_time": "0001-01-01T00:00:00Z"
  } ], "positions": { "perpetual_futures_positions": [], "expiring_futures_positions": [], "prediction_market_positions": [] } } ]
}
```

**Mapping to the Binance-shaped `executionReport`** (`%{"e" => "executionReport", "i", "s", "S",
"X", "x", "l", "L", "z", "q"}`):

| Binance field | From | Notes |
|---|---|---|
| `"i"` (orderId) | `order_id` | |
| `"s"` (symbol) | `product_id` → concat (strip `-`) | |
| `"S"` (side) | **`order_side`**, upcased | ⚠️ **NOT `side`** — the WS `user` channel names this field differently from every REST endpoint (which all use `side`). Easy cross-wiring mistake if the normalizer is copy-pasted from the REST-order-mapping code path. |
| `"X"` (status) | `status`, mapped per §2.5's table | Same enum as REST (`FILLED`/`OPEN`/`CANCELLED`/etc.), same "no distinct PARTIALLY_FILLED, derive from `OPEN` + partial `cumulative_quantity`" rule |
| `"x"` (exec type) | derived, same as OKX/Kraken pattern: `status: "FILLED"` and `cumulative_quantity` just increased → `"TRADE"`; `status: "OPEN"` and `cumulative_quantity == "0"` → `"NEW"`; `status: "CANCELLED"/"EXPIRED"/"FAILED"` → `"CANCELED"` | Coinbase's WS payload doesn't send a separate exec-type field either — same derivation burden as OKX |
| `"l"` (last fill qty) | not directly present in this event shape — **only cumulative** (`cumulative_quantity`) is sent, no per-fill delta field in the `user` channel's order object | ⚠️ implementers will likely need to diff `cumulative_quantity` against the previous known value for this order to derive a per-fill delta, since Coinbase doesn't hand you the incremental fill size the way Binance's `l`/OKX's `fillSz` do directly on the order-status push. Flag for implementer: this is a real gap vs. the other two adapters, not an oversight in this doc. |
| `"L"` (last fill price) | `avg_price` is cumulative-average, not last-fill price — same gap as above, no direct field | |
| `"z"` (cumulative fill qty) | **`cumulative_quantity`** | ⚠️ **NOT `filled_size`** — again, different field name from REST's `filled_size` for the same concept |
| `"q"` (orig qty) | not directly on this event either — order size isn't repeated here the way OKX/Kraken include it; implementers will likely need to keep the originally-placed size from the Create Order call/local order-tracking state rather than reading it off every WS push | |

This is a meaningfully "thinner" push payload than OKX's or Kraken's for building deltas — flagging
clearly for implementers so they don't assume feature parity with the other two adapters' WS
normalizers.

### Reconnect / re-auth rules

Not documented as explicitly as OKX's "must re-login and re-subscribe" rule, but logically follows
from the JWT-per-message requirement above: on any reconnect, a **fresh JWT** must be minted before
re-sending `subscribe` (the old one may already be within seconds of its 2-minute expiry, or fully
expired). `sequence_num` is present on every message — docs mention (paraphrased from a `WebFetch`
summary, **not independently re-confirmed with a second pass, flagging as lower-confidence**) that
gaps in `sequence_num` indicate dropped messages and should trigger a resync — this is standard
practice, not surprising, but I could not get a second independent source to quote the exact
guidance text, unlike everything else in this section.

---

## 5. Sandbox (`api-sandbox.coinbase.com`) — live-verified, with concrete proof of "static/canned"

### Base URL + auth

`https://api-sandbox.coinbase.com/api/v3/brokerage/{resource}` — **confirmed via live `curl` that
no `Authorization` header is needed at all**; docs state this explicitly (*"Users can make API
requests to Advanced sandbox API without authentication"*) and live testing confirms it: every call
below succeeded with zero auth headers.

### Which endpoints exist

Per docs: *"Only Accounts and Orders related endpoints are currently available in the sandbox."*
**Live-confirmed**: `GET /accounts` → `200` with data. `GET /orders/historical/batch` → `200` with
data. `POST /orders` → `200` with data. `GET /products` → **`404`** (live-confirmed — products are
NOT available in sandbox, matching the docs' "Accounts and Orders only" claim exactly).

### Responses are static/canned — proven two ways, not just quoted from docs

1. **Byte-for-byte determinism**: `GET /accounts` called twice, several seconds apart →
   **identical MD5 hash both times**. Response data includes hardcoded dates from 2023
   (`"created_at":"2023-12-14T21:40:32.181Z"`), not anything resembling "now."
2. **The response completely ignores request input** — this is the strongest possible proof and
   was not something the docs claimed explicitly, only discovered by testing it live:
   ```
   POST /orders  body: {"client_order_id":"scout-test-0001","product_id":"BTC-USD",
                         "side":"BUY","order_configuration":{"market_market_ioc":{"quote_size":"10"}}}
   response: {"success":true,"success_response":{"order_id":"f898eaf4-...",
              "product_id":"BTC-USD","side":"SELL",                    ← SELL, not the BUY I sent!
              "client_order_id":"sandbox_success_order",               ← not "scout-test-0001"!
              "attached_order_id":""},
              "order_configuration":{"limit_limit_gtc":{...}}}         ← limit_limit_gtc, not market_market_ioc!
   ```
   Sent `side: BUY`, got back `side: SELL`. Sent `client_order_id: "scout-test-0001"`, got back a
   fixed `"sandbox_success_order"`. Sent `market_market_ioc`, got back a fixed
   `limit_limit_gtc` echo. **The sandbox literally does not read the request body for this
   endpoint** — it returns one fixed canned success shape regardless of input. A second call with an
   `X-Sandbox: insufficient_fund` header (a plausible-looking value based on docs' vague mention of
   "custom header to trigger pre-defined variance") produced the **exact same byte-identical
   response** — either that's not the right trigger-string (docs don't spell out the exact accepted
   values, and I couldn't find them independently), or that particular endpoint doesn't honor it;
   flagging as **unconfirmed** rather than claiming the header does nothing at all.

### WebSocket sandbox

**Not confirmed to exist.** No sandbox-specific WS host/URL was found in any docs page or SDK
constants (the SDK's `constants.py` only defines the two production WS URLs from §4, no sandbox
variant). Treat as **does not exist** unless a future scout finds otherwise — matches the docs'
sandbox page only ever mentioning REST Accounts/Orders coverage, nothing about WS.

### Testing limitations — explicit section per the task's ask

- **Sandbox smoke-test value**: genuinely useful for exactly one thing — proving the **wire-level
  plumbing** works (can the adapter build a correctly-shaped HTTP request, does the JSON deserialize
  into the expected struct/map shape, does the base-URL-swapping config work). It is **useless for
  behavioral testing** — you cannot use it to verify "did my order actually get the right side/size
  recorded," "did insufficient-funds actually get rejected," etc., because the response is
  hardcoded and ignores input entirely (proven above, not inferred). This is a stronger and more
  specific limitation than "static/canned" alone suggests — it's not just that the *data* is fake,
  the *behavior* (echoing what you sent) is also absent.
- **What this means for the E2E checklist a human would run**: sandbox is worth one line — "hit
  `POST /orders` and `GET /accounts` against `api-sandbox.coinbase.com` with no auth, confirm the
  adapter parses the (fixed) response into the expected internal struct without crashing." It is
  **not** a substitute for a real, funded, authenticated production smoke test the way OKX's demo
  trading (`x-simulated-trading` header, real matching engine, real order lifecycle) is — Coinbase
  has no OKX-style demo-trading equivalent at all. This puts Coinbase in a middle ground between
  Kraken (no sandbox at all, only `validate=true` dry-run against live credentials) and OKX (full
  parallel demo-trading environment with a real matching engine): Coinbase's sandbox exists and
  needs no credentials, but is shallower than OKX's and cannot exercise any actual order-lifecycle
  logic.
- **Unit tests** (per the env rules, canned fixtures only, no network calls) should use the exact
  JSON shapes quoted verbatim in §2 (Create/Cancel/List/Get Order, Accounts, Products, Candles) and
  §4 (WS ticker/user/heartbeats) as fixture data — all of which are either the docs' own official
  examples or this scout's own live-pulled real responses, both suitable as byte-accurate fixtures.

---

## 6. Rate limits

### WebSocket — confirmed, hard numbers

> "Advanced Trade API WebSocket connections are rate-limited at **750 per second per IP address**."
> "Advanced Trade API WebSocket unauthenticated messages are rate-limited at **8 per second per IP
> address**."

(Quoted from `docs.cdp.coinbase.com/coinbase-business/advanced-trade-apis/websocket/websocket-rate-limits`
— the "coinbase-business" doc tree mirrors "coinbase-app" content for this topic; content matched
on a second independent fetch attempt.)

### REST — **could not find a current, dedicated Advanced Trade REST rate-limit page; flagging as an open gap, not guessing a number**

Extensive searching (multiple `WebSearch`/`WebFetch` passes, plus raw-HTML sidebar-link discovery
the way the Kraken scout did) did not turn up a live, current, Advanced-Trade-specific REST
rate-limit page under `docs.cdp.coinbase.com/coinbase-app/advanced-trade-apis/**`. Several search
results surfaced numbers like "5 requests/sec, burst 10/sec" or "30 req/s" — **these all trace back
to the OLD, separate "Coinbase Exchange" (formerly Coinbase Pro) product's docs
(`docs.cdp.coinbase.com/exchange/...`), which is a different API with different auth
(HMAC-based, not JWT) and a different base host entirely. Do NOT use Exchange-product rate-limit
numbers for the Advanced Trade / CDP-key API this plan targets** — I'm calling this out explicitly
because it's an easy mistake for a future implementer doing their own quick search to make (several
of my own search results conflated the two before I dug into which product each result was
actually about).

What **is** confirmed: the SDK's `constants.py` defines
`X_RATELIMIT_LIMIT`/`X_RATELIMIT_REMAINING`/`X_RATELIMIT_RESET` header name constants
(`x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset`) and the `RESTClient` accepts a
`rate_limit_headers=True` constructor flag that surfaces those headers on every response object —
i.e. **the API does return standard rate-limit headers on live responses**, which is the
recommended way for the Elixir adapter to self-throttle adaptively (read `x-ratelimit-remaining` /
back off near zero) rather than hardcoding an RPS number this scout could not verify. A `429` status
is the documented over-limit response (confirmed via multiple independent sources, consistent with
every other exchange's convention).

**Recommendation for implementers**: don't hardcode a Coinbase REST RPS constant the way the OKX/Kraken
adapters might (those had confirmed numbers). Read and respect the `x-ratelimit-*` response headers
instead, and treat this as an open item to verify against a real account before going live (a real
authenticated call would show the actual numeric limit in the header — something this credential-less
scouting pass cannot do).

---

## 7. Summary of surprises for implementers

1. **USDT-quoted spot pairs are a small minority (23 of 925, ~2.5%) on Coinbase**, vs. USD+USDC
   covering ~87% of the catalog — and are likely **entirely unavailable to EU/EEA accounts** since
   March 2025 due to MiCA (Tether isn't MiCA-authorized). This app's Binance-style
   `BASEUSDT`-concat-symbol assumption does not transfer cleanly to Coinbase; prefer USD/USDC quote
   resolution, treat USDT resolution as best-effort. **This is the single highest-impact finding in
   this document for anyone actually wiring up symbol resolution.**
2. **No `aud` claim in the official SDK's JWT construction** (ground-truth source), contradicting an
   earlier general-CDP-docs summary that claimed `aud: ["cdp_service"]` is required — went with the
   SDK's actual behavior as higher-confidence, flagged the discrepancy explicitly in §1.
3. **JOSE (already locked at 1.11.12 in this umbrella's `mix.lock`, zero lockfile changes needed) can
   build and round-trip-verify an ES256 JWT from Coinbase's exact SEC1 `-----BEGIN EC PRIVATE
   KEY-----` PEM format with custom `kid`/`nonce` headers** — proven with a live Elixir script run
   in this repo's own `_build`, not just asserted from docs. `{:jose, "~> 1.11"}` is the correct dep
   declaration.
4. **A fresh JWT is required for every WebSocket message**, not just once at connect — the 2-minute
   `exp` window applies per-message, stricter than REST (where it's naturally per-call anyway).
5. **The WS `user` channel's field names for order/side/qty (`order_side`, `cumulative_quantity`)
   differ from the REST order endpoints' field names (`side`, `filled_size`) for the same
   concepts** — an easy copy-paste bug if the normalizer reuses REST field names for the WS path.
6. **The WS `user` channel doesn't send per-fill delta size/price** (`"l"`/`"L"` Binance
   equivalents) — only cumulative figures — implementers need to diff against previously-seen state
   to derive a per-fill delta, unlike OKX/Kraken which hand you the delta directly.
7. **No `PARTIALLY_FILLED` value in Coinbase's `status` enum** (REST or WS) — must derive from
   `status == "OPEN"` (or `FILLED`-with-partial-cumulative on WS) + a nonzero-but-incomplete fill
   amount, same pattern the Kraken scout found for `OpenOrders`.
8. **`CANCELLED` is spelled with a double L** in every Coinbase status enum value — do not
   accidentally write the American `CANCELED` spelling when pattern-matching Coinbase's raw field
   value (only the app's own normalized output uses the single-L `CANCELED`).
9. **The sandbox (`api-sandbox.coinbase.com`) needs zero authentication** and its responses are not
   merely static but **actively ignore the request body** (live-proven: sent `side: BUY`, got back
   `side: SELL`) — even more limited for behavioral testing than "static/canned" alone implies; only
   useful for wire-plumbing smoke tests, never for behavior verification.
10. **REST rate limits for Advanced Trade specifically could not be pinned down to a hard number** in
    current docs (WS limits *are* confirmed: 750 conn/s/IP, 8 unauth msg/s/IP) — multiple search
    results conflate this product with the old, separate "Coinbase Exchange" API's different,
    documented (but inapplicable) rate limits; recommend reading the live `x-ratelimit-*` response
    headers adaptively instead of hardcoding a number.
11. **Order creation's success response doesn't include price/qty/status** — only
    `order_id`/`product_id`/`side`/`client_order_id` — a mandatory follow-up `GET` order-details
    call is needed to build the full Binance-shaped order map, same "GET after placing" pattern the
    OKX adapter already uses.
