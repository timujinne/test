# Kraken Spot API — Verified Facts (Task 0 scout)

Source of truth: `https://docs.kraken.com/api/docs/` (the official "Kraken Developers" docs, a
Mintlify-based SPA that redirects e.g. `docs.kraken.com/api/docs/guides/spot-rest-auth/` →
`docs.kraken.com/exchange/guides/rest/authentication`). Fetched/cross-checked 2026-07-10.

**Method note (read this first)**: `WebFetch` against these pages returns a *summarized* window of
a very large single-page-app HTML blob and is not fully reliable for exact strings (confirmed by
the OKX scout too). Wherever a fact is load-bearing, I did one of:
1. Downloaded the raw HTML with `curl -L` and grepped/parsed the embedded JSON/JSX text directly
   with Python (bypasses the summarizer entirely — this is the highest-confidence method and is
   how the signature worked example and rate-limit numbers below were pulled).
2. Called Kraken's **public, unauthenticated, read-only** REST API directly with `curl` (allowed
   per the "public endpoints are safe to test live-read-only" rule) — this is how all the symbol
   examples in §3 were obtained; they are **live production data**, not docs excerpts.
3. Cross-checked with a second independent WebFetch/WebSearch pass and, for anything algorithmic,
   independently recomputed it in **both Python and Elixir** and confirmed identical output.

No live authenticated calls (AddOrder, CancelOrder, OpenOrders, Balance, GetWebSocketsToken) were
made — no credentials exist for this scouting task and the env rules forbid it anyway. Everything
private-endpoint-shaped below is sourced from the docs (including one endpoint's **own official
worked example with fixed inputs**, which I verified byte-for-byte).

---

## 1. REST base URL + auth recipe

**Base URL**: `https://api.kraken.com`. Public paths: `/0/public/<Method>`. Private paths:
`/0/private/<Method>` (e.g. `/0/private/AddOrder`, `/0/private/Balance`). Confirmed both via docs
text and live `curl` against `https://api.kraken.com/0/public/AssetPairs`.

### Headers on every **private** REST call

| Header | Value |
|---|---|
| `API-Key` | HTTP header — "the public key from your API key-pair" (sent as-is, plaintext key id, not secret) |
| `API-Sign` | HTTP header — the computed signature (see below) |

Quoting the docs verbatim: *"For the REST API, the following parameters are used for
authentication to endpoints which contain private data: `API-Key` HTTP header parameter: the
public key from your API key-pair. `API-Sign` HTTP header parameter: encrypted signature of
message. `nonce` payload parameter: always increasing, unsigned 64-bit integer. `otp` payload
parameter: one-time-password and is only required if additional 2FA is configured for API."*

Note `nonce` (and optional `otp` for accounts with 2FA-for-API enabled) are **POST body /
form-payload params**, not headers — different from OKX which puts everything in headers.

Content-Type: **not explicitly mandated anywhere in the docs I could find** (grepped the raw HTML,
no hit). The POST body is a form-urlencoded `key=value&key=value` string (see "Encoded Payload" in
the worked example below); every reference client/SDK sends it as
`application/x-www-form-urlencoded` by convention. Recommend implementers do the same.

### Signature algorithm (API-Sign)

Docs' own one-line summary (confirmed via two independent sources: the official
`spot-rest-auth` guide and the `support.kraken.com` KB article, word-for-word identical):

> **"HMAC-SHA512 of (URI path + SHA256(nonce + POST data)) and base64 decoded secret API key"**

Expanded, step by step (this is Kraken's own reference Python, reproduced across `docs.kraken.com`
and `support.kraken.com` identically):

```python
encoded    = (nonce + postdata).encode()          # nonce as string, POST data as form-urlencoded string
sha256_dig = hashlib.sha256(encoded).digest()
message    = urlpath.encode() + sha256_dig         # urlpath = "/0/private/<Method>", NOT including query string (private calls have none)
secret_key = base64.b64decode(secret_b64)           # secret from key-pair, base64-DECODED first
signature  = base64.b64encode(hmac.new(secret_key, message, hashlib.sha512).digest())
```

Elixir shape:
```elixir
secret_key = Base.decode64!(secret_b64)
message = urlpath <> :crypto.hash(:sha256, nonce <> postdata)
signature = :crypto.mac(:hmac, :sha512, secret_key, message) |> Base.encode64()
```

Important gotcha baked into the recipe: `nonce` is concatenated **twice** — once raw before
`postdata`, and again as the literal `nonce=<value>` substring *inside* `postdata` itself (because
`postdata` is the full form-urlencoded body, which always includes the `nonce` field). This is not
a typo; it's confirmed identically in both independent sources and in the worked example below.
`urlpath` is always `/0/private/<Method>` with **no query string** — private Kraken calls never use
query params, everything (including `nonce`) goes in the POST body, so there's no OKX-style
"query string counts as part of the path" ambiguity to worry about.

### Fully-worked signature example — Kraken's OWN official docs example, independently verified

This is not a synthetic example — it's the **exact worked example table Kraken publishes in their
own `spot-rest-auth` guide** (extracted from the raw page HTML, not the WebFetch summary, to avoid
any risk of paraphrase-induced error). I then independently recomputed the signature in both
Python and Elixir from scratch and got a **byte-for-byte match** with Kraken's documented output —
this triple-source agreement is the strongest possible confidence for a unit-test fixture.

Inputs (Kraken's own docs, verbatim):
```
Private Key    = kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg==
Nonce          = 1616492376594
Encoded Payload (POST data) = nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25
URI Path       = /0/private/AddOrder
```

Expected `API-Sign` (Kraken's own documented output):
```
4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ==
```

Independently recomputed in Python (`hashlib`/`hmac`/`base64`, fresh process, no copy-paste of the
expected value into the computation):
```python
import base64, hashlib, hmac

secret_b64 = "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg=="
api_secret = base64.b64decode(secret_b64)
api_path   = "/0/private/AddOrder"
nonce      = "1616492376594"
postdata   = "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25"

encoded       = (nonce + postdata).encode()
sha256_digest = hashlib.sha256(encoded).digest()
message       = api_path.encode() + sha256_digest
signature     = base64.b64encode(hmac.new(api_secret, message, hashlib.sha512).digest()).decode()
# => "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ=="  ✔ MATCH
```

Independently recomputed in Elixir (`:crypto`/`Base`, copy-pasteable into the adapter's unit test):
```elixir
secret_b64 = "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg=="
api_secret = Base.decode64!(secret_b64)
api_path   = "/0/private/AddOrder"
nonce      = "1616492376594"
postdata   = "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25"

encoded       = nonce <> postdata
sha256_digest = :crypto.hash(:sha256, encoded)
message       = api_path <> sha256_digest
signature     = :crypto.mac(:hmac, :sha512, api_secret, message) |> Base.encode64()
# => "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ=="  ✔ MATCH
```

Both independently ran and both produced the exact expected signature — use this whole table
directly as `Kraken.Auth` unit test fixture data.

### Nonce rules

- "The value for the `nonce` payload body parameter is an always increasing, unsigned 64-bit
  integer for each request that is made with a particular API key." A UNIX timestamp in
  milliseconds is Kraken's own suggested generation method (matches the worked example's
  `1616492376594`, which is exactly `2021-03-23T09:19:36.594Z` in epoch-ms).
- "There is no way to reset the nonce for an API key to a lower value" — pick a monotonic source
  (epoch-ms is fine as long as you never call twice in the same ms with a naive `System.os_time`;
  safer to keep a monotonically-incrementing counter/last-used-nonce in adapter state and take
  `max(now_ms, last_nonce + 1)`).
- **Nonce window**: a per-key setting (default `0`) in the Kraken account UI that tolerates
  slightly-out-of-order nonces within a short window (e.g. 1s, 10s) to absorb network reordering.
  Only relevant if you have concurrent requests from the same key; doesn't change what we send,
  just widens what the server accepts. See §5.

---

## 2. Response envelope + endpoints

### Envelope (confirmed on every endpoint fetched)

```json
{"error": [...], "result": {...}}
```

- `error` is always present; empty array `[]` means success. Non-empty means failure — `result`
  is typically absent/null in that case.
- Error string format: **`"<Severity><Category>:<Message>"`** — Severity is `E` (error) or `W`
  (warning); Category is one of `General`, `API`, `Query`, `Order`, `Trade`, `Funding`, `Service`.
  Verbatim examples from docs/KB: `"EGeneral:Invalid arguments"`, `"EAPI:Invalid key"`,
  `"EAPI:Invalid signature"`, `"EAPI:Invalid nonce"`, `"EQuery:Unknown asset pair"`,
  `"EOrder:Insufficient funds (insufficient user funds)"`, `"EOrder:Cannot open position"`,
  `"EService:Unavailable"`, `"EGeneral:Internal error"`.

### AddOrder — `POST /0/private/AddOrder`

Required: `nonce`, `pair` (altname or pair id, e.g. `"XBTUSD"`), `type` (`"buy"`|`"sell"`),
`ordertype`, `volume` (string, base-currency quantity).

`ordertype` enum (confirmed): `market`, `limit`, `iceberg`, `stop-loss`, `take-profit`,
`stop-loss-limit`, `take-profit-limit`, `trailing-stop`, `trailing-stop-limit`,
`settle-position`. We only need `market`/`limit`.

Other params relevant to this app:
- `price` — required for `limit` (and stop/take-profit variants); string.
- `validate` (boolean) — **"If set to `true` the order will be validated only, it will not trade
  in the matching engine."** This is Kraken's dry-run flag (see §6). Docs don't explicitly confirm
  whether the JSON response still includes a `txid` when `validate=true`; **flagging as
  unconfirmed** — implementers relying on `validate=true` for a smoke test should not assume
  `result.txid` is present, and should branch on it defensively.
- `userref` (int32, optional) and `cl_ord_id` (string, optional, our own client order id) — **"This
  field is mutually exclusive with `userref` parameter"** (and vice versa) — pick one, not both.
  `cl_ord_id` accepts a long UUID (`6d1b345e-2821-40e2-ad83-4ecb18a06876`), a short/no-dash UUID, or
  free text up to 18 chars (e.g. `"arb-20240509-00010"`).
- `oflags` (comma-delimited): `post` (post-only, limit orders only), `fcib` (fee preference: pay
  fee in base currency — default when selling), `fciq` (fee preference: pay fee in quote currency
  — default when buying; mutually exclusive with `fcib`), `nompp` (**deprecated** — market price
  protection can no longer be disabled), `viqc` (market **buy** orders only: `volume` is expressed
  in quote currency instead of base — Kraken's rough equivalent of OKX's `tgtCcy: quote_ccy`; omit
  this flag to keep `volume` in base currency, matching Binance `quantity` semantics that the
  strategy layer expects).
- `timeinforce`: `GTC` | `IOC` | `GTD` | `FOK` (GTD needs `expiretm`).
- `expiretm` — "Expiry time on GTD orders can be set up to one month in future."

Example success response:
```json
{"error": [], "result": {"descr": {"order": "buy 1.45 XBTUSD @ limit 27500.0"}, "txid": ["OU22CG-KLAF2-FWUDD7"]}}
```
`txid` is a list (Kraken supports multi-leg conditional orders producing >1 txid; for plain
market/limit spot orders it's a 1-element list) — take `hd(txid)` as the Binance-shaped
`"orderId"`.

### CancelOrder — `POST /0/private/CancelOrder`

Required: `nonce`, and **one of** `txid` (Kraken order id, e.g. `"OHYO67-6LP66-HMQ437"` — can also
be a `userref`) or `cl_ord_id`.

```json
{"error": [], "result": {"count": 1}}
```
No per-order status detail — `count` is just how many orders matched and were canceled. To confirm
the resulting order state, re-query (OpenOrders/QueryOrders) or rely on the WS `executions`
stream's `order_status: "canceled"` push.

### OpenOrders — `POST /0/private/OpenOrders`

Required: `nonce`. Optional: `trades` (bool, include fills), `userref`, `cl_ord_id` (both filters).

```json
{
  "error": [],
  "result": {
    "open": {
      "OQCLML-BW3P3-BUCMWZ": {
        "refid": null, "userref": 0, "status": "open",
        "opentm": 1688666559.8974, "starttm": 0, "expiretm": 0,
        "descr": {"pair": "XBTUSD", "type": "buy", "ordertype": "limit", "price": "30010.0"},
        "vol": "1.25000000", "vol_exec": "0.37500000", "cost": "11253.7", "fee": "0.00000",
        "price": "30010.0", "misc": "", "oflags": "fciq", "trades": ["TCCCTY-WE2O6-P3NB37"]
      }
    }
  }
}
```

Note `result.open` is a **map keyed by txid**, not a list — the txid is the map key, not a field
inside the value. `descr.pair` is in **altname** form (`"XBTUSD"`, not the internal `"XXBTZUSD"`
pair-id) — same form you'd pass back into AddOrder/CancelOrder.

**Status vocabulary confirmed: `pending`, `open`, `closed`, `canceled`, `expired`.** In practice
`/OpenOrders` only ever surfaces `pending` (scheduled, not yet live — `starttm` in the future) or
`open` — closed/canceled/expired orders drop out of the open-orders set (Kraken has separate
`ClosedOrders`/`QueryOrders` REST endpoints for post-terminal-state lookups, not required by this
plan's endpoint list but worth knowing they exist if a "get final order state via REST" fallback is
ever needed instead of relying on the WS executions stream).

**There is no separate `PARTIALLY_FILLED` status value on this endpoint** — an order that's
partially filled still shows `status: "open"` with `vol_exec > 0` and `vol_exec < vol`.
Implementers must derive `PARTIALLY_FILLED` themselves: `status == "open" and vol_exec > "0"` →
`PARTIALLY_FILLED`, `status == "open" and vol_exec == "0"` → `NEW`. (The WS v2 `executions` channel
*does* have a distinct `partially_filled` enum value — see §4 — so this REST-vs-WS asymmetry only
matters if something ends up polling OpenOrders instead of/in addition to the WS stream.)

### Balance — `POST /0/private/Balance`

Required: `nonce`. Returns **totals only**, no available/locked split:
```json
{"error": [], "result": {"ZUSD": "171288.6158", "XXBT": "1011.1908877900", "USDT": "500000.00000000"}}
```
Keys are **internal asset codes** (X/Z-prefixed legacy ones included, see §3), not altnames —
`"XXBT"` not `"XBT"`/`"BTC"`, `"ZUSD"` not `"USD"`. Values are plain **decimal strings**, no
free/locked breakdown.

Because the app's `get_account/1` contract needs `"free"`/`"locked"` per Binance's shape, use
**`BalanceEx`** instead (`POST /0/private/BalanceEx`, same auth, same `nonce`-only required param)
— confirmed richer response:
```json
{"error": [], "result": {"ZUSD": {"balance": 25435.21, "hold_trade": 8249.76}, "XXBT": {"balance": 1.2435, "hold_trade": 0.8423}}}
```
`balance` = total, `hold_trade` = amount held for open orders → maps to Binance `"locked"`.
Optional `credit`/`credit_used` fields only appear "if the account has a credit line" (margin);
absent for a plain spot account. Docs' own formula: **`available = balance + credit - credit_used
- hold_trade`** — for a non-margin spot account this simplifies to `free = balance - hold_trade`.
Note `BalanceEx` values here are **numbers** (JSON floats), not strings like plain `Balance` — worth
a defensive `to_string`/`Decimal.new` in the normalizer either way.

### Public: AssetPairs — `GET /0/public/AssetPairs`

Query params: `pair` (comma-separated altnames/wsnames/ids to filter, optional — omit for all
pairs), `info` (`info`|`leverage`|`fees`|`margin`), `country_code`, `aclass_base`,
`execution_venue`, `assetVersion`. No auth required.

Full field list (live-verified, see §3 for real examples): `altname`, `wsname`, `aclass_base`,
`base`, `aclass_quote`, `quote`, `lot`, `pair_decimals`, `cost_decimals`, `lot_decimals`,
`lot_multiplier`, `leverage_buy`, `leverage_sell`, `fees`, `fees_maker`, `fee_volume_currency`,
`margin_call`, `margin_stop`, `ordermin`, `costmin`, `tick_size`, `status`
(`online`/other — only trade `online` pairs), `long_position_limit`, `short_position_limit`.

### Public: Ticker — `GET /0/public/Ticker`

Query param: `pair` (optional; default all pairs). No auth.
```json
{"error": [], "result": {"XXBTZUSD": {
  "a": ["30300.10000","1","1.000"], "b": ["30300.00000","1","1.000"],
  "c": ["30303.20000","0.00067643"], "v": ["4083.67001100","4412.73601799"],
  "p": ["30706.77771","30689.13205"], "t": [34619,38907],
  "l": ["29868.30000","29868.30000"], "h": ["31631.00000","31631.00000"], "o": "30502.80000"
}}}
```
`a`=[ask, whole-lot-vol, lot-vol], `b`=[bid, ...], `c`=[last-trade-price, last-trade-volume],
`v`=[vol-today, vol-24h], `p`=[vwap-today, vwap-24h], `t`=[trades-today, trades-24h],
`l`=[low-today, low-24h], `h`=[high-today, high-24h], `o`=today's-open (single value, not pair).
For the Binance-shaped ticker map: `"c"` (last price) ← `c[0]`; `"s"` ← the pair converted to
concat form (§3). Result keys are the **internal pair id** (`"XXBTZUSD"`), not altname — another
place implementers need the id→concat translation table.

### Public: OHLC — `GET /0/public/OHLC`

Required: `pair`. Optional: `interval` (minutes; valid: `1,5,15,30,60,240,1440,10080,21600`),
`since` (incremental fetch cursor). No auth.
```json
{"error": [], "result": {"XXBTZUSD": [[1688671200,"30306.1","30306.2","30305.7","30305.7","30306.1","3.39243896",23]], "last": 1688672160}}
```
Row shape: `[time, open, high, low, close, vwap, volume, count]` (note: **vwap is 6th, not
close-adjacent** — easy to mis-index against Binance's kline array which has a different field
order/count entirely; don't reuse a Binance kline parser verbatim). Up to 720 rows; last row is the
current, still-forming candle. `last` is the cursor to pass as `since` on the next incremental
call.

---

## 3. Symbols — the messy part, exhaustive

This is all **live-verified** against `https://api.kraken.com/0/public/AssetPairs` and
`/0/public/Assets` (public, unauthenticated, read-only — safe per the testing rules), not just
copied from docs prose.

### The three name variants + who expects which

| Variant | Example (BTC/USD) | Used where |
|---|---|---|
| **Pair id** (internal, X/Z-prefixed) | `XXBTZUSD` | Top-level dict **key** in `AssetPairs`, `Ticker`, `OHLC` REST responses. Also accepted as a `pair` input value (but altname is more readable/standard for our own outgoing requests). |
| **altname** | `XBTUSD` | What you **send** as `pair` in `AddOrder`/`CancelOrder`/etc, and what comes back in `descr.pair` in `OpenOrders`/order objects. **This is the canonical REST-facing pair identifier for our adapter.** |
| **wsname** | `XBT/USD` | The pair name for **WebSocket v1** (legacy, not used by this plan) subscriptions. **Do NOT use this for WebSocket v2** — see below, this is the #1 trap. |

### The WS v2 trap: `wsname` is WRONG for WebSocket v2 — v2 uses `BTC`, not `XBT`

Kraken's own troubleshooting docs, verbatim: *"If you are getting the error 'Currency pair not
supported XBT/USD' that is because we are using `BTC` instead of `XBT` for bitcoin in v2."*

Confirmed independently via the WS v2 `instrument` channel's own canonical example: subscribing to
`{"channel": "instrument"}` returns pairs with `"symbol": "BTC/USD"`, `"base": "BTC"`,
`"quote": "USD"` — **no X/Z prefixes at all**, and BTC is spelled `BTC` not `XBT`. Same rename
applies to the WS v2 `ticker` channel (its own docs example subscribes with `"symbol": "ALGO/USD"`
— plain ticker code, slash-separated, no legacy prefix) and the `executions` channel (its own
example push has `"symbol": "BTC/USD"`).

**So there are effectively two different "clean" symbol namespaces**, and they disagree specifically
on Bitcoin's ticker:
- **REST `altname`** (after stripping any legacy X-prefix on the *asset*, see below): `XBTUSD` →
  concat `XBTUSD` — still says **XBT**.
- **WS v2 `symbol`**: `BTC/USD` — says **BTC**.

Practical recommendation for implementers: build the concat↔Kraken-pair table from REST
`AssetPairs` (since that's what AddOrder/CancelOrder/Balance need anyway), applying a manual
`"XBT" → "BTC"` substitution when deriving the Binance-style concat symbol, and **separately** query
the WS v2 `instrument` channel (or maintain the same one hardcoded substitution) to get the
symbol string to put in WS `subscribe` frames — don't try to reuse `wsname` for v2, and don't
assume the REST and WS v2 pair-naming will ever converge on their own.

### Which assets keep a legacy letter and which don't (live-verified via `/0/public/Assets`)

Kraken's original (pre-2019ish) assets used ISO-4217-style codes with an `X` (crypto) or `Z` (fiat)
namespace prefix on the *internal* code. Over time Kraken **dropped the prefix from `altname` for
most of them**, but **two well-known cryptos kept a residual letter in their altname because that
letter is part of their actual legacy ticker, not a Kraken-added prefix**:

| Internal code | `altname` | Note |
|---|---|---|
| `XETH` | `ETH` | prefix stripped |
| `XLTC` | `LTC` | prefix stripped |
| `XXRP` | `XRP` | prefix stripped |
| `XXLM` | `XLM` | prefix stripped |
| `XXMR` | `XMR` | prefix stripped |
| `XETC` | `ETC` | prefix stripped |
| `XZEC` | `ZEC` | prefix stripped |
| `XREP` | `REP` | prefix stripped |
| **`XXBT`** | **`XBT`** | **kept** — `XBT` is Bitcoin's actual legacy ISO-4217-style ticker, Kraken's outer `X` is the namespace prefix (`X` + `XBT` = `XXBT`); altname strips only the namespace prefix, leaving `XBT` |
| **`XXDG`** | **`XDG`** | **kept**, same pattern — Dogecoin's legacy code is `XDG`; `X` + `XDG` = `XXDG` |
| `ZUSD`/`ZEUR`/`ZGBP`/`ZJPY`/`ZCAD` | `USD`/`EUR`/`GBP`/`JPY`/`CAD` | fiat Z-prefix always stripped cleanly, no exceptions found |
| `USDT`, `ADA`, `SOL` (and other post-2019 listings) | same as internal code | no prefix ever existed |

**Practical consequence**: to go from Kraken's `altname` to a Binance-style concat symbol, exactly
**two substrings need manual translation** app-wide: `"XBT"` → `"BTC"` and `"XDG"` → `"DOGE"`.
Every other asset's `altname` is already identical to its common ticker and needs no translation.
(I verified these two live; I did not exhaustively test every one of Kraken's ~300+ listed assets,
so there's a small chance of a third obscure legacy-code holdout — recommend building the
concat-to-Kraken lookup table from a live `AssetPairs` fetch at startup/cache-refresh time with
these two substitutions applied, rather than hardcoding a static symbol list, so any undiscovered
edge case degrades to "pair not found" instead of silently mismapping.)

The same `XBT`/`XDG` substitution is also needed for **`Balance`/`BalanceEx` asset keys** (which
use the *internal* code, e.g. `XXBT`, `USDT`, `ZUSD`) when building the Binance-shaped
`%{"balances" => [%{"asset" => ..., ...}]}` list — strip any `X`/`Z` namespace prefix, then apply
the two substitutions, e.g. `"XXBT"` → strip outer `X` → `"XBT"` → substitute → `"BTC"`;
`"ZUSD"` → strip `Z` → `"USD"` (no substitution needed); `"USDT"` → already bare, no change.

### Does Kraken have USDT quote pairs?

**Yes, confirmed live.** `XBT/USDT` exists (`altname: "XBTUSDT"`), and unlike the USD pair, the
quote-side `USDT` does **not** get a `Z` prefix at all — it's just `"USDT"` internally and as
altname (USDT is a "modern" listing, per the table above). This is worth calling out because it
means the "does every quote asset get a prefix" assumption is false — prefixing is specific to the
original small set of legacy assets, not a general rule.

### Three concrete, live-verified mapping examples

Pulled directly from `curl https://api.kraken.com/0/public/AssetPairs?pair=XBTUSDT,XBTUSD,ETHXBT`
on 2026-07-10 (trimmed to the relevant fields):

**1. BTC/USDT** (the BTC/XBT case, plus the "no prefix on USDT" case):
```
pair id (dict key) = XBTUSDT
altname             = XBTUSDT
wsname (v1 only)    = XBT/USDT
base                = XXBT        (→ strip X, substitute XBT→BTC → "BTC")
quote               = USDT        (→ no change, "USDT")
WS v2 symbol        = BTC/USDT   (not directly confirmed live for this exact pair via the
                                   instrument channel, but derived with high confidence from the
                                   documented XBT→BTC rename + base/quote already being bare "USDT")
concat (Binance-style) = "BTCUSDT"
pair_decimals = 1, lot_decimals = 8, ordermin = "0.00005", tick_size = "0.1"
```

**2. BTC/USD** (the classic XBT/BTC + Z-fiat-prefix case):
```
pair id (dict key) = XXBTZUSD
altname             = XBTUSD
wsname (v1 only)    = XBT/USD
base                = XXBT   (→ "BTC")
quote               = ZUSD   (→ "USD")
WS v2 symbol        = BTC/USD  (directly confirmed via the WS v2 instrument/ticker channel examples)
concat (Binance-style) = "BTCUSD"
pair_decimals = 1, lot_decimals = 8, ordermin = "0.00005", tick_size = "0.1"
```

**3. ETH/BTC** (base-is-also-legacy-prefixed case, quote is the XBT/BTC one this time):
```
pair id (dict key) = XETHXXBT
altname             = ETHXBT
wsname (v1 only)    = ETH/XBT
base                = XETH   (→ "ETH", prefix stripped, no substitution needed)
quote               = XXBT   (→ "BTC", strip + substitute)
WS v2 symbol        = ETH/BTC  (derived; XBT→BTC rename applies uniformly per Kraken's own note)
concat (Binance-style) = "ETHBTC"
pair_decimals = 6, lot_decimals = 8, ordermin = "0.001", tick_size = "0.000001"
```

### Which AssetPairs fields build the mapping table

To build a full concat↔Kraken-pair table from one `AssetPairs` (or filtered) fetch: for each
`{pair_id: {altname, base, quote, ordermin, tick_size, pair_decimals, lot_decimals, status}}`
entry —
1. `status == "online"` filter (skip delisted/suspended pairs).
2. Binance-style concat symbol = `altname` with `"XBT"→"BTC"` and `"XDG"→"DOGE"` substring
   substitution applied (covers both base and quote sides in one pass since it's a plain string
   op on the already-concatenated altname — no need to separately transform `base`/`quote`).
3. Store `altname` itself as the value to send back as `pair` in AddOrder/CancelOrder (i.e. keep
   the untranslated Kraken-native form for outgoing requests; only the concat form is translated,
   for matching against Binance-shaped symbols elsewhere in the app).
4. `tick_size` (or `10^-pair_decimals`, they should agree) → Binance `PRICE_FILTER.tickSize`;
   `10^-lot_decimals` → `LOT_SIZE.stepSize`; `ordermin` → also usable as `LOT_SIZE.minQty`.

---

## 4. WebSocket v2 (`wss://ws.kraken.com/v2`)

Public and private channels share the **same URL** (unlike OKX's separate `/public`/`/private`
endpoints) — auth happens per-subscription via a `token` field in the `params`, not at the
connection level.

### `ticker` channel (public)

Subscribe:
```json
{"method": "subscribe", "params": {"channel": "ticker", "symbol": ["ALGO/USD"]}}
```
Example snapshot/update push (Kraken's own canonical example, confirmed):
```json
{
  "channel": "ticker", "type": "snapshot",
  "data": [{
    "symbol": "ALGO/USD", "bid": 0.10025, "bid_qty": 740.0, "ask": 0.10036, "ask_qty": 1361.44813783,
    "last": 0.10035, "volume": 997038.98383185, "vwap": 0.10148, "low": 0.09979, "high": 0.10285,
    "change": -0.00017, "change_pct": -0.17, "timestamp": "2023-09-25T09:04:31.742648Z"
  }]
}
```
`type` is `"snapshot"` on first push after subscribing, `"update"` thereafter — same field shape
either way. For the Binance-shaped ticker map: `"c"` (last price) ← `last`; `"s"` ← `symbol` with
the `"/"` stripped and (if it says `"BTC"`) left as-is since our concat table already uses `BTC`
(no XBT→BTC substitution needed on the *WS* side — that substitution is a REST-only concern since
WS v2 already speaks `BTC` natively).

### `executions` channel (private) — order/fill updates

**Auth**: obtain a token via REST `POST /0/private/GetWebSocketsToken` (same HMAC-SHA512 auth
recipe as §1, just another private endpoint — `nonce` is the only required body param), then pass
it in the subscribe frame:
```json
{"method": "subscribe", "params": {"channel": "executions", "token": "G38a1tGFzqGiUCmnegBcm8d4nfP3tytiNQz6tkCBYXY", "snap_orders": true, "snap_trades": true}}
```
`snap_orders`/`snap_trades: true` requests an initial snapshot of current open orders/recent trades
on subscribe (useful for reconciling state after a reconnect).

Example execution push (Kraken's own canonical example):
```json
{
  "order_id": "OK4GJX-KSTLS-7DZZO5", "order_userref": 3, "exec_id": "TGBB7L-HT5LX-J3BZ4A",
  "exec_type": "trade", "trade_id": 62887576, "symbol": "BTC/USD", "side": "sell",
  "last_qty": 0.005, "last_price": 26599.9, "liquidity_ind": "t", "cost": 132.9995,
  "order_type": "limit", "timestamp": "2023-09-22T10:33:05.709993Z",
  "order_status": "partially_filled", "cum_qty": 0.005, "cum_cost": 132.9995, "avg_price": 26599.9,
  "order_qty": 0.005, "fee_usd_equiv": 0.3458, "fees": [{"asset": "USD", "qty": 0.3458}]
}
```
(Real pushes are wrapped in `{"channel": "executions", "type": "update"|"snapshot", "data": [...]}`
— the object above is one element of `data`.)

**`order_status` enum (confirmed)**: `pending_new`, `new`, `partially_filled`, `filled`,
`canceled`, `expired`.

**`exec_type` enum (confirmed)**: `pending_new`, `new`, `trade`, `filled`, `iceberg_refill`,
`canceled`, `expired`, `amended`, `restated`, `status`.

### Mapping to Binance-shaped `executionReport`

| Binance field | From | Notes |
|---|---|---|
| `"i"` (orderId) | `order_id` | |
| `"s"` (symbol) | `symbol` | already `"BTC/USD"` style in WS v2 — strip `"/"` to concat, no XBT/DOGE substitution needed (see above) |
| `"S"` (side) | `side` upcased | `"buy"`/`"sell"` |
| `"X"` (status) | `order_status` mapped: `pending_new`→`NEW`, `new`→`NEW`, `partially_filled`→`PARTIALLY_FILLED`, `filled`→`FILLED`, `canceled`→`CANCELED`, `expired`→`CANCELED` (Binance-shape contract only has 4 buckets; treat `expired` as terminal-non-fill, same bucket as `canceled` — mirrors how the OKX adapter folds `mmp_canceled` into `CANCELED`) | |
| `"x"` (exec type) | `exec_type` | Kraken conveniently **does** send a distinct exec-type field (unlike OKX, which required deriving it from `state`) — `trade`→`"TRADE"`, `new`/`pending_new`→`"NEW"`, `canceled`/`expired`→`"CANCELED"`, `filled` alone (no accompanying `trade`) is unlikely but map to `"TRADE"` too if seen |
| `"l"` (last fill qty) | `last_qty` | only meaningful on `exec_type: "trade"` pushes |
| `"L"` (last fill price) | `last_price` | ditto |
| `"z"` (cumulative fill qty) | `cum_qty` | |
| `"q"` (orig qty) | `order_qty` | base-currency quantity — confirm this stays base-denominated even when the original REST order used `oflags: viqc` (quote-denominated `volume`); **unconfirmed from docs**, flagging as a risk analogous to OKX's `tgtCcy` caveat — recommend never using `viqc` from this app's own outgoing orders so `order_qty`/`q` is always base-denominated for orders we place ourselves |

### Token lifetime — **ambiguous / contradictory docs, flagged explicitly**

Two official Kraken pages disagree:

1. The `GetWebSocketsToken` REST endpoint's own doc text: *"The token should be used within 15
   minutes of creation, but it does not expire once a successful Websockets connection and private
   subscription has been made and is maintained."* (i.e. implies a maintained connection keeps the
   token valid indefinitely.)
2. The dedicated WebSocket authentication guide: *"Tokens expire **15 minutes** after creation. To
   maintain uninterrupted access: Obtain a new token before the current one expires by calling
   `GetWebSocketsToken` again. After reconnecting, re-subscribe using the fresh token."* (i.e.
   flatly says it expires regardless of connection state, full stop.)

These are genuinely contradictory as written. **Safe engineering choice**: don't rely on doc #1's
"maintained connection = no expiry" claim. Refresh the token proactively (e.g. every ~10–12
minutes) and always fetch a fresh one on reconnect, per doc #2's explicit instructions — this
satisfies both interpretations and costs nothing (`GetWebSocketsToken` is a cheap, low-rate-impact
private call). If a subscribe uses an expired/invalid token, the server replies with
`{"errorMessage": "Token is expired", ...}` in the subscription-status message — treat that as a
signal to fetch-and-resubscribe immediately regardless of the refresh timer.

`GetWebSocketsToken` response: `{"error": [], "result": {"token": "...", "expires": 900}}` —
`expires` is always `900` (seconds = 15 min), consistent across both docs pages; it's only the
*meaning* of that number under a long-lived connection that's disputed.

### Heartbeat / ping-pong

- **Heartbeat channel** (automatic, no subscribe needed): *"Heartbeat messages are sent
  approximately once every second in the absence of any other channel updates."* Push shape:
  `{"channel": "heartbeat"}`. Generated automatically once you're subscribed to any channel — you
  cannot subscribe to it directly, and it stops appearing while other traffic is flowing (it only
  fills the silence).
- **Application-level ping** (distinct from the WS-protocol-level ping/pong): client → server
  `{"method": "ping", "req_id": 101}`, server replies `{"method": "pong", "req_id": 101,
  "time_in": "...", "time_out": "..."}` (RFC3339 timestamps). `req_id` is optional, echoed back if
  present.
- **No explicit disconnect-timeout threshold is documented** (unlike OKX's clear ~30s rule) — I
  could not find a number for "how long without traffic before Kraken closes the socket."
  Recommend a defensive client-side pattern: treat the ~1/sec heartbeat (or any channel traffic) as
  the primary liveness signal; if nothing arrives for some conservative window (e.g. 10s), send an
  app-level `ping` and expect a `pong`; if that also times out, treat the connection as dead and
  reconnect with backoff. This is inference/best-practice, not a documented Kraken rule — flagging
  as such.

---

## 5. Rate limits

Pulled directly from the raw HTML of `docs.kraken.com/api/docs/guides/spot-rest-ratelimits` and
`.../spot-ratelimits` (bypassing the WebFetch summarizer per the method note).

### Private (non-trading) REST endpoints — counter by API key

| Tier | Max counter | Decay rate |
|---|---|---|
| Starter | 15 | −0.33/sec |
| Intermediate | 20 | −0.5/sec |
| Pro | 20 | −1/sec |

Increment: **Ledger/trade-history calls add 2** to the counter; **all other private calls
(Balance, BalanceEx, OpenOrders, GetWebSocketsToken, etc.) add 1**. AddOrder/CancelOrder are
**not** counted here — they have their own separate trading-specific counter below.

### Trading endpoints (AddOrder/CancelOrder) — separate counter, per pair

| Tier | Max counter | Decay rate | Max open orders/pair |
|---|---|---|---|
| Starter | 60 | −1/sec | 60 |
| Intermediate | 125 | −2.34/sec | 80 |
| Pro | 180 | −3.75/sec | 225 |

Increment: **AddOrder always +1**. **CancelOrder cost depends on order age at cancel time** —
canceling very shortly after placing is *much* more expensive:

| Order age at cancel | Counter cost |
|---|---|
| < 5s | +8 |
| < 10s | +6 |
| < 15s | +5 |
| < 45s | +4 |
| < 90s | +2 |
| < 300s | +1 |
| ≥ 300s | (lowest tier, effectively +1 or less) |

Implication for any strategy that places-then-quickly-cancels (e.g. a market-maker or a
grid-rebalance-on-every-tick pattern): rapid cancel churn burns the trading counter far faster than
placement does — something to keep in mind when porting the `Grid` strategy to Kraken.

### Public endpoints

Rate limited **by IP address** (not API key — no auth needed to hit them at all). *"Calling the
public endpoints at a frequency of 1 per second (or less) would remain within the rate limits."*
`Trades` and `OHLC` are additionally limited **per currency pair**, not just per IP.

### General

*"There is a shared limit across REST, Websockets and FIX."* Going over limit causes calls to be
"restricted for a few seconds (or possibly longer if calls continue to be made while the rate
limits are active)" — i.e. it's a soft throttle/backoff situation, not an instant hard ban, but
hammering it while already limited extends the penalty.

### Nonce pitfalls

- Must be **strictly increasing per API key** — see §1. `EAPI:Invalid nonce` fires on a repeated or
  lower-than-previous nonce.
- Concurrent requests from the same key (e.g. two GenServers both calling the same account's
  Trader) are the most common trigger — the wall-clock-ms source can produce the same or
  out-of-order value under concurrency. Recommend serializing all private REST calls for a given
  Kraken account through a single process (matches this app's existing per-account Trader
  GenServer architecture — natural fit, no extra work needed) so nonce generation is inherently
  ordered.
- "Nonce window" (account-level setting, default 0) only widens server-side tolerance for
  network-reordering; it's not something the adapter sets or needs to know about beyond
  understanding why a support article mentions it.

---

## 6. Testing limitations

- **No public spot testnet.** Confirmed via WS FAQ search and general docs review — Kraken spot
  has no sandbox/demo host or demo API keys, unlike OKX (`x-simulated-trading` header) or Binance
  (`testnet.binance.vision`). This matches the plan-level note already given.
- **`validate=true` on AddOrder** is the only built-in dry-run mechanism: *"the order will be
  validated only, it will not trade in the matching engine."* It still requires a **live,
  authenticated** call with real credentials (parameter validation + presumably balance/permission
  checks happen against the real account) — it is explicitly **not** a way to test without
  credentials, and per the env rules must never be exercised from unit tests (only from a
  documented, human-run E2E checklist against a real funded account, same posture as the OKX demo
  trading caveat but even more restrictive since there's no separate demo keypair to isolate it).
  Whether `validate=true` returns a `txid` is unconfirmed from docs (see §2) — a live smoke test
  should check this once and record the answer in the E2E checklist doc, not assume either way.
- **What CAN be safely tested live, read-only, without credentials, right now** (all exercised
  during this scouting pass, safe for CI/dev-time smoke checks): `GET /0/public/AssetPairs`,
  `GET /0/public/Assets`, `GET /0/public/Ticker`, `GET /0/public/OHLC` — no auth, no rate-limit
  risk at reasonable call rates (≤1/sec), no account/funds involved. All of the live symbol
  examples in §3 came from exactly these calls.
- **What CANNOT be safely tested at all in this repo's CI/unit tests**: anything under
  `/0/private/*` (AddOrder, CancelOrder, OpenOrders, Balance, BalanceEx, GetWebSocketsToken) and
  the WS v2 `executions` channel (needs a token from a private call). Per the env rules, unit tests
  for these must use **canned/fixture responses** shaped like the examples quoted verbatim in §2
  and §4 — never a real authenticated call. The one exception already covered: the AddOrder
  signature algorithm itself (§1) can and should be a **pure, credential-free unit test** using the
  fake-secret worked example, since it never touches the network at all.

---

## 7. Summary of surprises for implementers

1. **Nonce is concatenated twice** in the signature prehash (once raw, once inside `postdata`) —
   easy to get wrong if you assume it's just `urlpath + sha256(postdata)`.
2. **REST and WebSocket v2 disagree on Bitcoin's ticker** (`XBT` vs `BTC`) and this is a
   documented, intentional rename in v2, not a bug — build the concat-symbol table with an
   explicit `XBT→BTC` (and `XDG→DOGE`) substitution, and don't reuse the REST `wsname` field for
   WS v2 subscriptions (it's the *v1* symbol format and will fail with "Currency pair not
   supported" on v2).
3. **`Balance` returns totals only**; you need the separate `BalanceEx` endpoint for the
   free/locked split the Binance-shape contract requires.
4. **REST `OpenOrders` has no `partially_filled` status value** — it's `status: "open"` +
   `vol_exec > 0`; only the WS v2 `executions` channel has a first-class `partially_filled` enum.
5. **Token lifetime docs contradict each other** (§4) — one page says a maintained connection never
   needs a refreshed token, another flatly says 15-minute hard expiry. Treated as a real
   ambiguity, resolved conservatively (proactive refresh).
6. **CancelOrder cost scales inversely with order age** on the trading rate-limit counter — placing
   then immediately canceling is 8x more expensive than placing and canceling 5 minutes later.
   Relevant to any tight-loop/market-making style strategy.
7. Kraken's docs site (`docs.kraken.com`, Mintlify-based) is summarization-unfriendly for
   `WebFetch` in the same way OKX's was — but unlike OKX, I was able to grep the raw HTML directly
   with `curl` + Python for the highest-stakes facts (the literal worked signature example, the
   rate-limit tables), which is strictly more reliable than relying on the summarizer twice. Future
   scouts on other exchanges: prefer `curl -L <url> | python3 -c '...'` grepping the raw
   Mintlify/Next.js JSON-in-HTML payload over repeated `WebFetch` calls whenever a fact is
   load-bearing and the first WebFetch pass looks incomplete or truncated.
