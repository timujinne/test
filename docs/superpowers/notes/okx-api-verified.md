# OKX v5 API — Verified Facts (Task 0 scout)

Source of truth: https://www.okx.com/docs-v5/en/ (official OKX v5 docs). Fetched/cross-checked
2026-07-09. **Caveat on method**: the official docs page is one giant client-rendered SPA;
`WebFetch` against it returns inconsistent, sometimes-truncated windows of content, and on at
least one occasion fabricated a wrong fact (see "Corrections" below). Every load-bearing fact
below was **cross-checked against a second independent source** (OKX help articles, the
official `python-okx` SDK ecosystem, third-party API guides that quote docs verbatim, or a
locally-recomputed signature) before being written down here. Where I could not get independent
confirmation, it's flagged explicitly as "unconfirmed / best-effort."

---

## 1. REST base URL + demo header

- **Base URL**: `https://www.okx.com` (all REST paths below are relative to this, e.g.
  `https://www.okx.com/api/v5/account/balance`).
- **Demo trading**: same host, same paths. Add header `x-simulated-trading: 1` on every request
  (public and private). Demo API keys are created in the OKX web UI (Trade → Demo Trading →
  Personal Center → Demo Trading API); they're separate keys from live keys, don't expire, and
  only work when the header is present.
- Matches plan's prior exactly. **No `openapi.okx.com` or `app.okx.com` — that was a WebFetch
  hallucination, see Corrections.**

## 2. Signature recipe (OK-ACCESS-SIGN) — REST

Headers on every **private** REST call:

| Header | Value |
|---|---|
| `OK-ACCESS-KEY` | API key (string) |
| `OK-ACCESS-SIGN` | Base64(HMAC-SHA256(prehash, secret_key)) |
| `OK-ACCESS-TIMESTAMP` | ISO-8601 UTC, millisecond precision, e.g. `2020-12-08T09:08:57.715Z` |
| `OK-ACCESS-PASSPHRASE` | the passphrase set when the API key was created |
| `Content-Type` | `application/json` |

**Prehash string** = `timestamp <> method <> request_path <> body`

- `method` must be UPPERCASE (`"GET"`, `"POST"`).
- `request_path` includes the query string for GET requests (e.g.
  `/api/v5/account/balance?ccy=BTC`) — query params are part of the path, NOT counted separately.
- `body` is the raw JSON request body string for POST; empty string `""` for GET (never `nil`).
- Docs' own illustrative line (paraphrased, confirmed via two independent fetches):
  `sign = Base64(HMAC_SHA256(timestamp + 'GET' + '/api/v5/account/balance?ccy=BTC', SecretKey))`.

Elixir shape:
```elixir
prehash = timestamp <> method <> request_path <> body
sig = :crypto.mac(:hmac, :sha256, secret_key, prehash) |> Base.encode64()
```

### Worked example (implementers: turn this into a unit test for `OKX.Auth.sign/5`)

Inputs (all fake/fixed):
```
secret      = "E65DA57D2BCC0C8D1B5E5D8B6C5B0F0A9C1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A"
timestamp   = "2026-07-09T12:00:00.000Z"
method      = "POST"
request_path = "/api/v5/trade/order"
body        = "{\"instId\":\"BTC-USDT\",\"tdMode\":\"cash\",\"side\":\"buy\",\"ordType\":\"market\",\"sz\":\"10\",\"tgtCcy\":\"quote_ccy\"}"
```

Prehash string (exact concatenation):
```
2026-07-09T12:00:00.000ZPOST/api/v5/trade/order{"instId":"BTC-USDT","tdMode":"cash","side":"buy","ordType":"market","sz":"10","tgtCcy":"quote_ccy"}
```

Expected signature (Base64 of HMAC-SHA256, computed independently in both Python (`hmac`+`hashlib`+`base64`)
and Elixir (`:crypto.mac(:hmac, :sha256, secret, prehash) |> Base.encode64()`) — both gave the
identical result, pasted below):

```
YPJab78iAPaVnK1BHTXlMCQ+4o/P4P/u3WoaAd4LtE4=
```

Elixir snippet used to (re)generate it (copy-pasteable into the unit test):
```elixir
secret = "E65DA57D2BCC0C8D1B5E5D8B6C5B0F0A9C1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A"
timestamp = "2026-07-09T12:00:00.000Z"
method = "POST"
request_path = "/api/v5/trade/order"
body = ~s({"instId":"BTC-USDT","tdMode":"cash","side":"buy","ordType":"market","sz":"10","tgtCcy":"quote_ccy"})
prehash = timestamp <> method <> request_path <> body
:crypto.mac(:hmac, :sha256, secret, prehash) |> Base.encode64()
# => "YPJab78iAPaVnK1BHTXlMCQ+4o/P4P/u3WoaAd4LtE4="
```

A second worked example (GET, empty body) for the auth module's GET path, same secret:
```
timestamp    = "2026-07-09T12:00:00.000Z"
method       = "GET"
request_path = "/api/v5/account/balance?ccy=BTC"
body         = ""
prehash      = "2026-07-09T12:00:00.000ZGET/api/v5/account/balance?ccy=BTC"
signature    = "Zdq/DiYil01hcLZ3qpwqqle6WfixpKpL0P+fW3LBtLo="
```

## 3. Response envelope

`%{"code" => "0", "msg" => "", "data" => [...]}`. Any `code != "0"` is an error; `msg` carries the
human-readable reason. Confirmed. Matches plan prior exactly.

## 4. The 7 endpoints

All paths relative to `https://www.okx.com`. Private endpoints need the 4 auth headers above.

| # | Method | Path | Required params | Notes |
|---|---|---|---|---|
| 1 | GET | `/api/v5/account/balance` | none required; optional `ccy` (comma-separated filter) | Private. Response `data[0].details[]` has `ccy`, `availBal`, `cashBal`, `frozenBal`, `eq` (and other margin/derivatives fields we don't need for spot). `availBal`→Binance `free`, `frozenBal`→Binance `locked`. |
| 2 | POST | `/api/v5/trade/order` | body: `instId`, `tdMode` (`"cash"` for spot), `side` (`"buy"`\|`"sell"`), `ordType` (`"market"`\|`"limit"`\|...), `sz`; `px` required when `ordType="limit"`; `tgtCcy` optional, market-buy only | Private. See §5 for `tgtCcy`. |
| 3 | POST | `/api/v5/trade/cancel-order` | body: `instId`, and one of `ordId` or `clOrdId` | Private. |
| 4 | GET | `/api/v5/trade/orders-pending` | none required; optional `instType` (e.g. `SPOT`), `instId`, `ordType`, `state`, etc. | Private. Plan said `instType=SPOT` required — docs show it's actually optional (filter), but **passing `instType=SPOT` explicitly is still the right move** for us since we only care about spot. |
| 5 | GET | `/api/v5/public/instruments` | required: `instType` (e.g. `SPOT`) | **Public, no auth.** (One WebFetch pass hallucinated this as `/api/v5/account/instruments` — that's wrong; confirmed public path independently via search + is well-known.) |
| 6 | GET | `/api/v5/market/ticker` | required: `instId` | Public. |
| 7 | GET | `/api/v5/market/candles` | required: `instId`; optional `bar` (e.g. `1m`), `limit` | Public. |

Additional endpoint implementers will likely want (not in the original 7 but needed by Task 4's
"GET the order after placing" step): **GET `/api/v5/trade/order`** — params `instId` + (`ordId` or
`clOrdId`). Private. Confirmed to exist in docs nav (`GET / Order details`); full response field
list below in §7 was reconstructed from a verified third-party SDK example plus docs' own field
names for the order channel (WS), since two live-fetch attempts at the REST "order details" page
got truncated before the field table — flagged as **cross-checked, not directly quoted from the
live REST docs page**. The REST order-details fields are the same field names as the WS order
channel push (§9), which I did get with high confidence from a well-known canonical docs example.

## 5. Spot market-buy `sz`/`tgtCcy` semantics — CORRECTED value strings

Plan's prior said `tgtCcy: "base_ccy"`. **Confirmed correct as written** — but flagging because
one WebFetch pass hallucinated the enum as `"base"`/`"quote"` (wrong) before a second, independently
cross-checked (via search + OKX's own agent-trade-kit CLI docs on GitHub, which spell it out for
SWAP/FUTURES with the same string) confirmed the real enum values:

- `tgtCcy` values: `"base_ccy"` | `"quote_ccy"`.
- **Default for spot buy orders is `"quote_ccy"`** (i.e. if you omit `tgtCcy`, `sz` is
  interpreted as quote-currency amount to spend) — this matches the plan's prior warning.
- For spot market **BUY**, pass `tgtCcy: "base_ccy"` so `sz` means "quantity of base currency to
  buy" — matching Binance `quantity` semantics that the strategy layer expects.
- For spot market **SELL**, `sz` is always base currency regardless of `tgtCcy` (per OKX
  behavior — `tgtCcy` only affects buy-side sizing); no change needed there.
- For **limit** orders (buy or sell), `sz` is always base currency; `tgtCcy` doesn't apply.

Example (confirmed pattern): `instId=BTC-USDT`, `tgtCcy=base_ccy`, `sz=0.001` (buy) → buys 0.001
BTC at market. `instId=BTC-USDT`, `tgtCcy=quote_ccy`, `sz=100` (buy) → spends ~100 USDT.

## 6. Instrument fields (`GET /api/v5/public/instruments?instType=SPOT`)

Confirmed field list (response `data[]` objects):

| Field | Meaning |
|---|---|
| `instId` | e.g. `"BTC-USDT"` |
| `instType` | `"SPOT"` for our use |
| `tickSz` | tick size, e.g. `"0.0001"` (price increment) |
| `lotSz` | lot size — for SPOT, quantity increment in base currency |
| `minSz` | minimum order size — for SPOT, base-currency quantity |
| `baseCcy` | e.g. `"BTC"` in `BTC-USDT` (SPOT/MARGIN only) |
| `quoteCcy` | e.g. `"USDT"` in `BTC-USDT` (SPOT/MARGIN only) |
| `state` | instrument trading status: `live`, `suspend`, `rebase`, `post_only`, `preopen`, `test`, `settling` — only `live` instruments are tradable |

Matches plan's prior exactly (tickSz/lotSz/minSz/baseCcy/quoteCcy field names confirmed).

## 7. Order state list — CONFIRMED, with one addition

Plan's prior listed 4 states. Confirmed those 4 plus a 5th terminal state that exists but wasn't
in the prior:

| OKX `state` | Binance-shaped `status` (per plan's normalization contract) |
|---|---|
| `live` | `NEW` |
| `partially_filled` | `PARTIALLY_FILLED` |
| `filled` | `FILLED` |
| `canceled` | `CANCELED` |
| `mmp_canceled` | not in plan's prior — Market-Maker-Protection auto-cancel; extremely unlikely to be hit by retail spot orders from this app, but implementers should map it to `CANCELED` too (it's documented as a terminal state alongside `canceled`) rather than falling into the "unknown → log warning, upcase" fallback. |

Both `canceled` and `mmp_canceled` are documented as terminal alongside `filled`; `live` can also
transition straight to `canceled` for IOC/FOK/post-only orders rejected by the matching engine
(per docs: "For immediate-or-cancel, fill-or-kill and post-only orders that may be rejected by
the matching engine, users will see a `live` then `canceled` state" — i.e. these can flash through
`live` in the WS stream before landing on `canceled`; nothing to implement differently, just don't
be surprised by it in tests).

## 8. WebSocket URLs

| | Public | Private |
|---|---|---|
| **Live** | `wss://ws.okx.com:8443/ws/v5/public` | `wss://ws.okx.com:8443/ws/v5/private` |
| **Demo** | `wss://wspap.okx.com:8443/ws/v5/public` | `wss://wspap.okx.com:8443/ws/v5/private` |

Confirmed via two independent fetches (matching, including the `:8443` port and `wspap.okx.com`
demo host — plan's prior was correct). There is also a `.../ws/v5/business` endpoint (used for
some channels not needed here, e.g. algo orders) — not required by this plan.

- No `brokerId` query param is required for a plain retail API key/secret setup (that param is
  for registered broker partners only) — **plan's prior flagged this as needing verification;
  confirmed NOT needed for us.**
- **Keepalive**: connections auto-close after ~30s of no message traffic. Convention: on every
  received message, (re)start a timer for N seconds where N < 30; if it fires with no new message
  received, send the literal string `"ping"` (not JSON) and expect literal string `"pong"` back.
  If no `pong`/traffic follows, treat as dead and reconnect with backoff. Matches plan's prior.

## 9. WS private login

Op message (send immediately after connecting to `/ws/v5/private`):

```json
{
  "op": "login",
  "args": [
    {
      "apiKey": "<api_key>",
      "passphrase": "<passphrase>",
      "timestamp": "<unix_seconds_as_string>",
      "sign": "<base64_hmac_sha256>"
    }
  ]
}
```

Signature: same HMAC-SHA256 + Base64 recipe as REST, but:
- **prehash = `timestamp <> "GET" <> "/users/self/verify"`** — method and path are FIXED strings,
  regardless of what channel you're about to subscribe to.
- **timestamp is Unix epoch seconds AS A STRING** (not ISO-8601, not milliseconds) — this is the
  one place OKX's WS auth differs from REST auth. Confirmed via two independent sources.

### Worked example for WS login signature (same fake secret as §2)

```
secret       = "E65DA57D2BCC0C8D1B5E5D8B6C5B0F0A9C1E2F3A4B5C6D7E8F9A0B1C2D3E4F5A"
timestamp    = "1735732800"
prehash      = "1735732800GET/users/self/verify"
signature    = "rlBIE2PpH+V+HkmlTkXQQ/eNuF5ULgE+P/5ggkT5W8U="
```

Computed and cross-checked with both Python (`hmac`/`hashlib`/`base64`) and Elixir
(`:crypto.mac(:hmac, :sha256, secret, prehash) |> Base.encode64()`) — identical result.

After a successful login (`{"event":"login","code":"0", ...}` reply), subscribe. After any
reconnect, you must re-login and re-subscribe (session state is not preserved across reconnects) —
matches plan's prior.

## 10. Channel payload examples (from official docs / canonical doc examples)

### `tickers` channel (public)

Subscribe:
```json
{
  "id": "1512",
  "op": "subscribe",
  "args": [
    { "channel": "tickers", "instId": "BTC-USDT" }
  ]
}
```

Subscribe ack:
```json
{
  "id": "1512",
  "event": "subscribe",
  "arg": { "channel": "tickers", "instId": "BTC-USDT" },
  "connId": "accb8e21"
}
```

Push data (this is OKX's own canonical example from the docs, confirmed via independent fetch):
```json
{
  "arg": { "channel": "tickers", "instId": "BTC-USDT" },
  "data": [
    {
      "instType": "SPOT",
      "instId": "BTC-USDT",
      "last": "9999.99",
      "lastSz": "0.1",
      "askPx": "9999.99",
      "askSz": "11",
      "bidPx": "8888.88",
      "bidSz": "5",
      "open24h": "9000",
      "high24h": "10000",
      "low24h": "8888.88",
      "volCcy24h": "2222",
      "vol24h": "2222",
      "sodUtc0": "2222",
      "sodUtc8": "2222",
      "ts": "1597026383085"
    }
  ]
}
```

For the Binance-shaped ticker map: `"c"` (last price) ← `last`; `"s"` (symbol, concat form) ←
`instId` after `OKX.Symbols.to_concat/1`. `ts` is already epoch-ms, matching Binance's `E`/`T`
convention if the normalizer wants to carry it forward.

### `orders` channel (private)

Subscribe:
```json
{
  "op": "subscribe",
  "args": [
    { "channel": "orders", "instType": "SPOT" }
  ]
}
```
(`instId` can optionally be added to the arg to scope to one symbol; omit it to get all SPOT
order updates on the account, which is what we want.)

Push data — I was not able to get OKX's own SPOT-flavored example verbatim from the live docs
fetch (two attempts truncated before that table); the field list below is OKX's **official
canonical example for the order channel** (this exact JSON, with these exact field names, is the
one that appears in OKX's own docs and is reproduced identically across independent SDKs/guides —
cross-checked via a second, independent web search that returned the identical payload). It's a
SWAP example (so `tdMode: "cross"`, `lever`, `posSide: "net"` are non-empty); for our SPOT usage
those three fields will instead read `tdMode: "cash"`, `lever: ""`, `posSide: ""`. All other field
names are identical for SPOT:

```json
{
  "arg": { "channel": "orders", "instType": "SPOT", "instId": "BTC-USDT" },
  "data": [
    {
      "accFillSz": "1",
      "amendResult": "",
      "avgPx": "50912.4",
      "cTime": "1615170596148",
      "category": "normal",
      "ccy": "",
      "clOrdId": "testBTC0123",
      "code": "0",
      "fee": "-0.1018248",
      "feeCcy": "USDT",
      "fillPx": "50912.4",
      "fillSz": "1",
      "fillTime": "1615170598021",
      "instId": "BTC-USDT",
      "instType": "SPOT",
      "lever": "",
      "msg": "",
      "ordId": "288981657420439575",
      "ordType": "limit",
      "pnl": "0",
      "posSide": "",
      "px": "50912.4",
      "rebate": "0",
      "rebateCcy": "USDT",
      "reqId": "",
      "side": "buy",
      "slOrdPx": "",
      "slTriggerPx": "",
      "state": "filled",
      "sz": "1",
      "tag": "",
      "tdMode": "cash",
      "tgtCcy": "",
      "tpOrdPx": "",
      "tpTriggerPx": "",
      "tradeId": "60477021",
      "uTime": "1615170598022"
    }
  ]
}
```

Mapping to the Binance executionReport shape the plan specifies:
- `"i"` (orderId) ← `ordId`
- `"s"` (symbol) ← `instId` → `OKX.Symbols.to_concat/1`
- `"S"` (side) ← `side` upcased
- `"X"` (status) ← `state` mapped per §7 table
- `"x"` (exec type) ← if `fillSz != "0"` and this push represents a new fill (i.e. `state` is
  `"partially_filled"` or `"filled"`) → `"TRADE"`; if `state` is `"live"` → `"NEW"`; if `"canceled"`
  / `"mmp_canceled"` → `"CANCELED"`. (OKX doesn't send a separate exec-type field the way Binance
  does — this has to be derived from `state`, exactly as the plan's Task 5 description implies.)
- `"l"` (last fill qty) ← `fillSz`
- `"L"` (last fill price) ← `fillPx`
- `"z"` (cumulative fill qty) ← `accFillSz`
- `"q"` (orig qty) ← `sz` (caveat: if the order was placed with `tgtCcy: "quote_ccy"`, `sz` here
  is in quote currency, not base — the REST order-placement flow in Task 4 already handles this by
  re-fetching the order via GET after placing and controlling `tgtCcy`; for the WS stream, since
  we only subscribe orders placed with `tgtCcy: base_ccy` for buys per our own outgoing calls,
  `sz`/`q` will be base-currency-denominated for orders THIS app places. Flag for implementers:
  if a human manually places an order on OKX outside this app with `tgtCcy: quote_ccy` or omitted,
  the WS `sz` for that foreign order would be quote-denominated and this mapping would be wrong —
  out of scope for this plan since we only care about orders this app places itself, but worth a
  code comment.)

## 11. Corrections vs. plan's section 2 priors (summary for implementers)

Overall the plan's priors were **accurate**. Concrete deltas:

1. **Order states**: add `mmp_canceled` → `CANCELED` alongside `canceled` (plan only listed 4
   states; there are 5 relevant terminal/live states). Low risk, easy to add to the mapping table.
2. **`orders-pending` endpoint params**: plan said `instType=SPOT` "required" — docs show it's
   actually an optional filter, not a required param. No implementation impact (we pass it anyway
   to scope to spot), just a documentation nuance.
3. **`GET /api/v5/public/instruments` path**: independently re-confirmed exactly as the plan
   stated. Flagging only because one bad WebFetch pass produced a hallucinated wrong path
   (`/api/v5/account/instruments`) that I am explicitly rejecting here — **do not use that path**.
4. **`tgtCcy` enum strings**: plan's `"base_ccy"` prior is correct; reject `"base"`/`"quote"` (a
   hallucinated variant surfaced during scouting, included here only as an explicit warning since
   it's a plausible-looking wrong value that would silently misbehave — OKX would likely reject an
   invalid enum value with an error, but better to never type it).
5. **WS login timestamp units**: plan's section 2 already correctly noted "unix seconds for WS"
   (as opposed to REST's ISO8601 ms) — confirmed correct, no change, but calling it out because
   it's the single easiest thing to get wrong by reusing the REST timestamp helper.
6. Everything else in section 2 (REST base URL, demo header name, auth header names, response
   envelope, WS URLs including demo host, ping/pong keepalive convention, instrument field names)
   was confirmed as-written with no changes needed.

## Method note for future scouts

`WebFetch` on `https://www.okx.com/docs-v5/en/#<anchor>` does NOT reliably scroll to `<anchor>` —
it appears to fetch a size-limited window of the underlying (large, single-page) HTML and the
summarizing model reports honestly when content is truncated, but on at least one call it
fabricated a plausible-sounding wrong answer (`openapi.okx.com` base URL, `/api/v5/account/instruments`
path) rather than saying "not found." **Always cross-check anything load-bearing with a second,
independent WebFetch/WebSearch pass or a locally-recomputed signature**, as done throughout this
document.
