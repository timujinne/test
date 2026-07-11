# Kraken + Coinbase Adapters + Automation Improvements — Implementation Spec

**Date:** 2026-07-10 · **Branch:** `worktree-kraken-coinbase` · **Base:** local `master` @ `791067f` (already contains a fully working OKX adapter)

**Goal:** Add Kraken and Coinbase as fully working exchanges (mirroring the OKX adapter's proven
pattern exactly — same file layout, same Binance-shape normalization strategy, same
credentials-map behaviour, same registry/UI wiring), plus land the scout's top-picked automation
fixes from `docs/superpowers/notes/automations-review.md`. After this spec is implemented: a user
can add a Kraken account (API key + secret, no passphrase) or a Coinbase account (key name +
EC-PEM secret, no passphrase) in the UI, and run existing strategies (Naive/Grid/DCA/ConditionalChain)
against Kraken/Coinbase spot markets, with the same safety-relevant automation fixes OKX already
benefits from indirectly (crash-restart hygiene, subscription-leak fix, position tracking).

Source material (read before implementing any task):
- `docs/superpowers/notes/kraken-api-verified.md` — Kraken REST/WS facts, live-verified, worked HMAC-SHA512 signature vector.
- `docs/superpowers/notes/coinbase-api-verified.md` — Coinbase REST/WS facts, live-verified, worked ES256 JWT round-trip.
- `docs/superpowers/notes/automations-review.md` — the "TOP PICKS" ranked list Part C implements verbatim.
- `docs/superpowers/plans/2026-07-09-okx-adapter.md` — the structural template both adapters mirror.
- The OKX adapter source itself: `apps/data_collector/lib/data_collector/okx_client.ex`,
  `okx/auth.ex`, `okx/normalize.ex`, `okx/symbols.ex`, `okx_public_stream.ex`,
  `okx_private_stream.ex`, `okx_private_supervisor.ex`, `market_stream.ex`,
  `exchange_client.ex`, `exchange_registry.ex`.

---

## 0. What already exists (no re-work needed)

Unlike the original OKX plan, the credentials-map behaviour seam and the `passphrase` column are
**already merged** (verified in code, `git log` shows this branch is based on a master containing
the finished OKX adapter):

- `DataCollector.ExchangeClient` behaviour (`apps/data_collector/lib/data_collector/exchange_client.ex`)
  already takes a `credentials()` map (`%{api_key:, secret_key:, passphrase: String.t() | nil}`) on
  every private-endpoint callback. **Kraken and Coinbase both always pass `passphrase: nil`** —
  neither exchange uses one. `get_exchange_info/1` stays public/unauthenticated (symbol arg only).
- `SharedData.Schemas.ApiCredential` already has an encrypted `passphrase` field (nullable) and
  `@supported_exchanges ["binance", "okx"]` — this spec's UI tasks extend that list.
- `DataCollector.ExchangeRegistry.client_for/1` pattern-matches `"binance"`/`"okx"` today — extend
  with `"kraken"`/`"coinbase"` (never convert to atoms — security invariant, keep it).
- `DataCollector.MarketStream` facade (`subscribe/2`, `unsubscribe/2`) already dispatches
  `"binance"`/`"okx"` — extend the same way.
- `TradingEngine.Trader` already threads `state.credentials` (not separate `api_key`/`secret_key`)
  and already has the `exchange == "okx"` branch that calls `OKXPrivateStream.ensure_started/2` in
  `init/1` (trader.ex:107-109) — Kraken/Coinbase tasks add sibling branches, same shape.
- `TradingEngine.SymbolInfo` is already exchange-aware (`get_precision(exchange, symbol)`,
  ETS key `{exchange, symbol}`) — no changes needed there; Kraken/Coinbase's `get_exchange_info/1`
  just needs to return the right Binance-shaped filters and it plugs straight in.
- `apps/dashboard_web/lib/dashboard_web/live/settings_live.ex` already renders `<option>` elements
  for `kraken` and `coinbase` with `disabled` + "(coming soon)" (lines ~293-309) and already has the
  OKX passphrase-field conditional block (`@account_form[:exchange].value == "okx"`) — this spec's
  UI tasks flip `disabled` off for both and must NOT show a passphrase field for either (Kraken has
  none; Coinbase's two fields are just relabeled `api_key`/`secret_key`, see Task 8).

**KEY ARCHITECTURAL DECISION (carried over from the OKX plan, unchanged):** both adapters normalize
ALL payloads (REST and WS) INTO Binance-shaped maps. Every normalization must match the exact key
contracts already enforced by the OKX adapter and quoted in this worktree's system context:
- Order maps: `"orderId"`, `"clientOrderId"`, `"symbol"`, `"type"`, `"side"`, `"price"`, `"origQty"`,
  `"executedQty"`, `"status"`, `"timeInForce"`.
- Ticker events: at least `"s"` (concat symbol) and `"c"` (last price), broadcast as `{:ticker, map}`
  on `"market:#{concat}"`.
- Execution reports: `%{"e" => "executionReport", "i", "s", "S", "X", "x", "l", "L", "z", "q"}` on
  `"order_updates"` as `{:execution_report, map}`.
- `get_account/1` → `%{"balances" => [%{"asset", "free", "locked"}]}`.
- `get_exchange_info/1` → `%{"symbols" => [%{"symbol", "filters" => [PRICE_FILTER/tickSize, LOT_SIZE/stepSize]}]}`.
- Statuses normalized to exactly `NEW` / `PARTIALLY_FILLED` / `FILLED` / `CANCELED` (single-L,
  American spelling in the app's own output — even though Coinbase's raw field says `CANCELLED`).

**Environment gotchas (mandatory, repeated here for implementers):**
- Container exports `MIX_ENV=dev` — always run `MIX_ENV=test mix test ...`.
- `deps` is a symlink to `/app/deps` — never commit it; if a `mix.exs` change would alter
  `mix.lock`, **stop and report** instead of running `mix deps.get`.
- `mix format --check-formatted` scoped to files touched; `mix credo --strict` — introduce no new
  findings in touched files (repo-wide pre-existing findings in `chain_monitor.ex`/`nav_init.ex` are
  not yours to fix).
- Never `String.to_atom`/`String.to_existing_atom` on external input.
- Never log plaintext credentials (api keys, secrets, PEM keys, JWTs, WS tokens) — every new
  `Logger` call must be spot-checked.
- **No live orders, no authenticated live-exchange HTTP calls in tests.** Unit tests use canned
  fixtures only, copied verbatim from the two verified-notes files. Kraken has no public spot
  testnet (`validate=true` dry-run only, requires real credentials). Coinbase's sandbox returns
  static/input-ignoring canned responses (proven live by the scout) — neither is a CI testing tool.
- Commit after each task; never push.

---

## PART A — Kraken adapter

### Task 1 — Kraken config, nonce infrastructure, Auth, Symbols

**Files:**
- `apps/data_collector/lib/data_collector/kraken/auth.ex` (new)
- `apps/data_collector/lib/data_collector/kraken/symbols.ex` (new)
- `apps/data_collector/lib/data_collector/application.ex` (add `:kraken_nonce` ETS table)
- `config/runtime.exs`, `config/dev.exs`, `config/test.exs` (add `config :data_collector, :kraken, ...`)
- `.env.example` (add `KRAKEN_API_KEY`/`KRAKEN_SECRET_KEY`/`KRAKEN_BASE_URL` placeholders)

**Config shape** (mirror the OKX `config :data_collector, :okx` block exactly, read at runtime via
`Application.get_env`, never `compile_env`):
```elixir
config :data_collector, :kraken,
  base_url: System.get_env("KRAKEN_BASE_URL", "https://api.kraken.com"),
  ws_url: System.get_env("KRAKEN_WS_URL", "wss://ws.kraken.com/v2")
```
`config/test.exs` uses fixed mock values (deterministic regardless of host env vars), same pattern
as the existing OKX test block. Kraken has **no demo/testnet flag** — there is nothing to gate (see
verified notes §6); do not invent a `demo:` key.

**`DataCollector.Kraken.Auth`** — HMAC-SHA512 per verified notes §1, with the Kraken-documented,
independently-recomputed (Python + Elixir) worked example as the unit test fixture:

```elixir
@spec sign(secret_b64 :: String.t(), urlpath :: String.t(), nonce :: String.t(), postdata :: String.t()) :: String.t()
def sign(secret_b64, urlpath, nonce, postdata) do
  secret_key = Base.decode64!(secret_b64)
  encoded = nonce <> postdata
  sha256_digest = :crypto.hash(:sha256, encoded)
  message = urlpath <> sha256_digest
  :crypto.mac(:hmac, :sha512, secret_key, message) |> Base.encode64()
end
```
Unit test asserts byte-for-byte against the notes' worked example (secret
`kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg==`, urlpath
`/0/private/AddOrder`, nonce `1616492376594`, postdata
`nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25` → expected
`4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ==`). This is
a pure, credential-free, network-free test — safe under constraint (6).

**Nonce generation** (verified notes §1 gotcha: "always increasing, unsigned 64-bit integer",
"no way to reset for a lower value"). Implement as a monotonic counter backed by a public named ETS
table (same idiom as `:ticker_subscribers`/`:okx_public_subscribers`, already created in
`DataCollector.Application.start/2` — add one more line there: `:ets.new(:kraken_nonce, [:named_table, :public, :set])`).

```elixir
@spec next_nonce() :: String.t()
def next_nonce do
  seed = System.system_time(:millisecond)
  :ets.update_counter(:kraken_nonce, :counter, {2, 1}, {:counter, seed})
  |> Integer.to_string()
end
```
`:ets.update_counter/4`'s default-tuple form seeds the counter to the current epoch-ms on the very
first call (satisfies "start from something timestamp-shaped, survives no prior state") and every
subsequent call is a plain atomic `+1` (satisfies "always increasing", is race-safe across
concurrent callers within the VM without needing to compare against wall-clock on every call, and
never regresses even across a clock adjustment). Unit test: call `next_nonce/0` twice, assert the
second is numerically greater than the first (`String.to_integer/1` both sides), and that both are
valid decimal-digit strings.

**`DataCollector.Kraken.Auth.headers/3`** — builds `[{"API-Key", api_key}, {"API-Sign", signature},
{"Content-Type", "application/x-www-form-urlencoded"}]`. Unlike OKX's `Auth.headers/4`, this
function does **not** touch `credentials.passphrase` at all (Kraken has none) and does **not**
raise on a missing passphrase — there is nothing to validate. Signature: `headers(credentials,
urlpath, postdata)` where `postdata` is the exact already-built `nonce=...&...` form-urlencoded
string (see Task 3 — the same string is used as both the HTTP POST body and the signed payload, so
build it once and pass it to both `Auth.headers/3` and the HTTP call).

**`DataCollector.Kraken.Symbols`** — GenServer + public named ETS (`@table :kraken_symbols_cache`),
same lazy-load/refresh-once-on-miss pattern as `OKX.Symbols`, sourced from the **public,
unauthenticated** `GET /0/public/AssetPairs` (verified notes §2/§3 — no `pair` query param, fetch
everything, filter `status == "online"`). Public API:

- `to_pair/1` (concat, e.g. `"BTCUSD"` → Kraken `altname`, e.g. `"XBTUSD"`) — used as the `pair`
  value sent to AddOrder/CancelOrder/etc.
- `to_concat/1` (accepts **either** an `altname` (e.g. `"XBTUSD"`, as echoed in `descr.pair`) **or**
  a Kraken **pair id** (e.g. `"XXBTZUSD"`, as used for Ticker/OHLC dict keys) → concat, e.g.
  `"BTCUSD"`). Cache both key namespaces (`{:altname, ...}` and `{:pair_id, ...}`) pointing at the
  same concat value so one function handles both input shapes transparently.
- `to_ws_symbol/1` (concat → WS v2 symbol, e.g. `"BTCUSD"` → `"BTC/USD"`) — built from the
  substituted base/quote split at cache-build time (see below), **not** derived from `wsname`
  (verified notes §3: `wsname` is the WS v1 format and is wrong for v2 — never read it).
- `instrument_info/1` (concat → `%{tick_size: String.t(), step_size: String.t(), min_qty: String.t()}`,
  from `tick_size` (or `10 ** -pair_decimals` if `tick_size` absent), `10 ** -lot_decimals`, and
  `ordermin` respectively).

Every function returns `{:ok, _} | {:error, :unknown_symbol}`, same contract as `OKX.Symbols`.

Concat-symbol construction (verified notes §3, the load-bearing "messy part"): for each
`AssetPairs` entry keyed by pair id, with `altname`, `base`, `quote` fields — apply the **exactly
two** substring substitutions `"XBT" → "BTC"` and `"XDG" → "DOGE"` to the `altname` to get the
concat symbol (covers both base and quote sides in one string op, since `altname` is already the
concatenated form). Store the untranslated `altname` itself (not the substituted concat) as the
value for `to_pair/1` — outgoing REST calls must use Kraken's native `XBT`-spelled altname, only the
concat form used for matching against the rest of the app is translated. For `to_ws_symbol/1`,
apply the same two substitutions to `base` and `quote` **separately**, then join with `"/"`
(e.g. `base = "XXBT"` → strip prefix → `"XBT"` → substitute → `"BTC"`; `quote = "ZUSD"` → strip
prefix → `"USD"`; join → `"BTC/USD"`).

Also expose a **pure, stateless** helper (no ETS, no GenServer call — needed by `Normalize` for
`get_account/1`, which returns *asset* codes, not *pair* codes):

```elixir
@spec asset_code_to_ticker(String.t()) :: String.t()
def asset_code_to_ticker(code)
```
Strips a leading `X`/`Z` namespace prefix (only when the remainder is a plausible legacy code —
implement by checking against the fixed known set from verified notes §3: `XETH→ETH`, `XLTC→LTC`,
`XXRP→XRP`, `XXLM→XLM`, `XXMR→XMR`, `XETC→ETC`, `XZEC→ZEC`, `XREP→REP`, `XXBT→XBT`, `XXDG→XDG`,
`ZUSD→USD`, `ZEUR→EUR`, `ZGBP→GBP`, `ZJPY→JPY`, `ZCAD→CAD`; anything else (e.g. `"USDT"`, `"ADA"`)
passes through unchanged), **then** applies the `XBT→BTC`/`XDG→DOGE` substitution. Implement as a
literal pattern-match table (matches the project's "never derive atoms/behavior from unvalidated
external strings" spirit, and is trivially unit-testable against every example in verified notes
§3 — including the `"XXBT"→"BTC"`, `"ZUSD"→"USD"`, `"USDT"→"USDT"` cases the notes give verbatim).

**Fetch implementation**: same `HTTPoison.get` + `DataCollector.CircuitBreaker.call(:kraken_api,
fn -> ... end)` + `Jason.decode!` pattern as `OKX.Symbols.fetch_instruments/0`, hitting
`"#{base_url}/0/public/AssetPairs"` with no auth headers. Parse the `%{"error" => [], "result" =>
%{pair_id => entry}}` envelope; skip any pair id where `entry["status"] != "online"`.

**Tests:**
- `apps/data_collector/test/kraken/auth_test.exs` — the worked-example signature vector (POST
  worked example above), `next_nonce/0` monotonicity, `headers/3` shape (no passphrase key present
  anywhere in the output).
- `apps/data_collector/test/kraken_symbols_test.exs` — pure parsing tests against a canned
  `AssetPairs` JSON fixture built from the three live examples in verified notes §3 (BTC/USDT,
  BTC/USD, ETH/BTC) plus one non-`online` entry to prove it's filtered out. Assert `to_pair/1`,
  `to_concat/1` (both altname and pair-id input forms), `to_ws_symbol/1`, `instrument_info/1`, and
  `asset_code_to_ticker/1` all match the notes' three worked examples exactly, plus an
  `{:error, :unknown_symbol}` case for an unrecognized concat/pair. No live HTTP call in the test —
  factor the JSON-parsing function out of `fetch_instruments/0` the same way `OKX.Symbols.parse_instruments/1`
  is factored out, so it's directly unit-testable.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test/kraken apps/data_collector/test/kraken_symbols_test.exs`

---

### Task 2 — Kraken Normalize + KrakenClient (REST)

**Files:**
- `apps/data_collector/lib/data_collector/kraken/normalize.ex` (new)
- `apps/data_collector/lib/data_collector/kraken_client.ex` (new)

**`DataCollector.Kraken.Normalize`** — pure functions, no HTTP, mirrors `OKX.Normalize`'s shape:

- `order_status/1` — REST **OpenOrders**-shape derivation (verified notes §2: no distinct
  `PARTIALLY_FILLED` on this endpoint). Signature: `order_status(kraken_status :: String.t(),
  vol :: String.t(), vol_exec :: String.t()) :: String.t()`. `"pending"` → `"NEW"`; `"open"` with
  `Decimal.new(vol_exec) |> Decimal.gt?(Decimal.new(0))` → `"PARTIALLY_FILLED"`; `"open"` otherwise
  → `"NEW"`; `"closed"` → `"FILLED"`; `"canceled"` → `"CANCELED"`; `"expired"` → `"CANCELED"`;
  unknown → log `Logger.warning/1` and pass through upcased (same defensive convention as OKX).
- `ws_order_status/1` — separate mapping for the WS v2 `executions` channel's own distinct
  `order_status` enum (verified notes §4, which unlike REST *does* have `partially_filled` as a
  first-class value): `"pending_new"` → `"NEW"`, `"new"` → `"NEW"`, `"partially_filled"` →
  `"PARTIALLY_FILLED"`, `"filled"` → `"FILLED"`, `"canceled"` → `"CANCELED"`, `"expired"` →
  `"CANCELED"`, unknown → warn + upcase passthrough.
- `ws_exec_type/1` — Kraken's WS `exec_type` field maps almost directly (unlike OKX, which has to
  derive this): `"trade"` → `"TRADE"`, `"new"`/`"pending_new"` → `"NEW"`, `"canceled"`/`"expired"` →
  `"CANCELED"`, `"filled"` (no accompanying trade) → `"TRADE"`, `"amended"`/`"restated"`/`"status"`/
  `"iceberg_refill"` → pass through upcased (not part of the 4-bucket Binance contract, but
  harmless/unused by current strategy code, which only reads `"NEW"`/`"TRADE"`/`"CANCELED"`).
- `order_request/2` — Binance-format `order_params` (`%{symbol:, side:, type:, quantity:, price:,
  timeInForce:, client_order_id:}`) + the already-resolved Kraken `altname` (via
  `Kraken.Symbols.to_pair/1`) → the **map of body params** for AddOrder (nonce excluded here —
  added by `KrakenClient` right before signing/sending, see below). `type` `"MARKET"` →
  `ordertype: "market"`, `"LIMIT"` → `ordertype: "limit"`; `side` downcased; `volume:
  to_string(quantity)` — **always base-currency, no `viqc`/`tgtCcy`-equivalent flag needed**
  (verified notes §2: Kraken's `volume` is base-denominated by default for both market and limit
  orders unless the caller opts into `oflags: "viqc"`, which this adapter must never set — simpler
  than OKX here, call this out in a moduledoc note). `price: to_string(price)` only when present
  (limit orders). `timeinforce:` mapped from Binance `timeInForce` (`"GTC"`/`"IOC"`/`"FOK"` pass
  through unchanged; default to `"GTC"` if absent — Kraken's `GTD` is never used by this app, no
  `expiretm` support needed). `cl_ord_id: order_params.client_order_id` when present and non-empty
  (**never** set `userref` — the two are mutually exclusive per verified notes §2, and this app has
  no use for `userref`).
- `order_response_from_placement/2` — **deliberate design decision, documented here explicitly**:
  unlike OKX (which does a cheap "GET the order right after placing" follow-up), Kraken's AddOrder
  response only carries `descr`/`txid` (verified notes §2) with no price/qty/status detail, and the
  only alternative REST follow-up (`OpenOrders`) **won't contain the order at all if a market order
  filled instantly** (closed/filled orders drop out of the open-orders set immediately — verified
  notes §2). Rather than depend on an unverified endpoint (`QueryOrders`, only briefly mentioned in
  the notes, response shape not confirmed) or silently mis-report a vanished order, this adapter
  builds the Binance-shaped placement response **directly from the known request** and the AddOrder
  ack, with `"status" => "NEW"` and `"executedQty" => "0"` as the honest best-known state
  immediately after a synchronous placement call — the WS `executions` channel (Task 3) is the
  authoritative, fast-following source of truth for the real fill state from that point on, exactly
  the same "REST placement ack is provisional, WS confirms" pattern the rest of the app already
  relies on for Binance/OKX. Signature: `order_response_from_placement(order_params :: map(),
  txid :: String.t()) :: map()`, returns:
  ```elixir
  %{
    "orderId" => txid,
    "clientOrderId" => order_params[:client_order_id] || txid,
    "symbol" => order_params.symbol,
    "type" => String.upcase(order_params.type),
    "side" => String.upcase(order_params.side),
    "price" => order_params[:price] && to_string(order_params.price),
    "origQty" => to_string(order_params.quantity),
    "executedQty" => "0",
    "status" => "NEW",
    "timeInForce" => order_params[:timeInForce] || "GTC"
  }
  ```
- `open_order_response/2` — a single `OpenOrders` `result.open` **value** (the txid is the map
  *key*, passed in separately as `txid`) + concat symbol → Binance-shaped order map, reading
  `descr.ordertype`, `descr.type`, `descr.price`, `vol`, `vol_exec`, `status` and calling
  `order_status/3` above. `"clientOrderId"` — Kraken's OpenOrders entries don't echo back a client
  order id field in the documented shape; use the txid itself as a fallback (`"clientOrderId" =>
  txid`), matching the same "no better field available" fallback pattern used elsewhere.
- `cancel_response/2` — `(txid, concat_symbol)` → `%{"orderId" => txid, "status" => "CANCELED",
  "symbol" => concat_symbol}` given `result.count >= 1`.
- `account_response/1` — `BalanceEx` `result` map (`%{asset_code => %{"balance" => num, "hold_trade"
  => num}}`) → `%{"balances" => [%{"asset" => ticker, "free" => free_str, "locked" => hold_str}]}`.
  `ticker` via `Kraken.Symbols.asset_code_to_ticker/1`. `free = balance - hold_trade` (verified notes
  §2's own formula, simplified for a non-margin spot account); wrap both `balance`/`hold_trade`
  (JSON numbers, not strings, per notes) with `Decimal.new(to_string(value))` before subtracting,
  output both `free`/`locked` via `Decimal.to_string/1`.
- `exchange_info/2` — `(instrument_info, concat_symbol)` → same shape as OKX's `exchange_info/2`
  (`PRICE_FILTER`/`tickSize` ← `tick_size`, `LOT_SIZE`/`stepSize`+`minQty` ← `step_size`/`min_qty`).
- `ticker_event/2` — a single WS v2 `ticker` channel data item + concat symbol →
  `%{"e" => "24hrTicker", "s" => concat, "c" => to_string(last), "o" => nil, "h" => to_string(high),
  "l" => to_string(low), "v" => to_string(volume), "q" => nil}` (Kraken's ticker push has no direct
  24h-quote-volume field the way OKX's `volCcy24h` does — leave `"q"` as `nil`, no strategy code
  currently reads it off the ticker map; only `"s"`/`"c"` are load-bearing per the contract).
  `last`/`high`/`low`/`volume` arrive as JSON numbers in the WS payload (verified notes §4 example)
  — wrap with `to_string/1`, not `Decimal`, since Binance's own ticker fields are plain strings and
  no arithmetic happens on this map downstream.
- `execution_report/2` — a single WS v2 `executions` channel data item + concat symbol (already
  `/`-stripped, see Task 3 — **no** `Kraken.Symbols` lookup needed here, WS v2 already speaks `BTC`
  natively per verified notes §3) → 
  ```elixir
  %{
    "e" => "executionReport",
    "i" => order_id,
    "s" => concat_symbol,
    "S" => String.upcase(side),
    "X" => ws_order_status(order_status),
    "x" => ws_exec_type(exec_type),
    "l" => last_qty && to_string(last_qty),
    "L" => last_price && to_string(last_price),
    "z" => to_string(cum_qty),
    "q" => to_string(order_qty)
  }
  ```
  reading Kraken's WS field names `order_id`, `side`, `order_status`, `exec_type`, `last_qty`,
  `last_price`, `cum_qty`, `order_qty` (verified notes §4's canonical example — note these differ
  from the REST field names, e.g. `cum_qty` not `vol_exec`; don't cross-wire).

**`DataCollector.KrakenClient`** (`@behaviour DataCollector.ExchangeClient`), mirroring
`OKXClient`'s shape:

- `get_account/1`: `POST /0/private/BalanceEx` (not plain `Balance` — verified notes §2, `Balance`
  has no free/locked split) → `Normalize.account_response/1`.
- `create_order/2`: `Symbols.to_pair(order_params.symbol)` → `Normalize.order_request/2` → build
  the full body map with `nonce` merged in last (`Map.put(body, :nonce, Auth.next_nonce())`) →
  `URI.encode_query/1` → `postdata` → `POST /0/private/AddOrder` with that exact `postdata` string
  as both the HTTP body and the signed payload → on `%{"error" => [], "result" => %{"txid" =>
  [txid | _]}}`, `Normalize.order_response_from_placement(order_params, txid)`. On a non-empty
  `"error"` list, return `{:error, Enum.join(errors, "; ")}` (Kraken's own `"E..."`/`"W..."`
  category-prefixed strings, verified notes §2 — pass them through as-is, don't reparse them).
- `cancel_order/3`: body `%{txid: order_id}` (+ nonce) → `POST /0/private/CancelOrder` →
  `result.count >= 1` → `Normalize.cancel_response/2`; `count == 0` → `{:error, "Kraken CancelOrder:
  no matching open order (already closed, filled, or unknown txid)"}`.
- `get_open_orders/2`: `POST /0/private/OpenOrders` (body `%{trades: false}` + nonce; **no `pair`
  filter param exists on this endpoint** per verified notes §2) → iterate `result.open` (a **map
  keyed by txid**, not a list — `Enum.map(open, fn {txid, entry} -> ... end)`), resolve each
  entry's `descr.pair` (an **altname**) via `Symbols.to_concat/1`, build via
  `Normalize.open_order_response/2`. When called with a non-nil `symbol` arg, filter the resolved
  list client-side to entries whose resolved concat equals the requested symbol (no server-side
  filter available — mirror this client-side-filter necessity explicitly in a code comment so a
  future reader doesn't go looking for a missing Kraken query param). Unknown/unmapped `descr.pair`
  entries: log a warning and skip (same defensive convention as `OKXClient.fetch_open_orders/2`).
- `get_exchange_info/1`: `Symbols.instrument_info/1` → `Normalize.exchange_info/2`. No HTTP call of
  its own — same "owned by the Symbols module" pattern as OKX.

**Request plumbing** (`request/4` private helper, mirrors `OKXClient.request/4`): builds
`Auth.headers(credentials, urlpath, postdata)`, POSTs `postdata` as the raw form-urlencoded body to
`"#{base_url()}#{urlpath}"`, wraps the HTTP call in `DataCollector.CircuitBreaker.call(:kraken_api,
fn -> ... end)`, decodes the `%{"error" => [...], "result" => ...}` envelope: empty `error` list →
`{:ok, result}`; non-empty → `{:error, Enum.join(error, "; ")}`. GET requests (none needed for the
private endpoints this adapter uses — Kraken's private API is POST-only per verified notes §1) are
not implemented; do not add a `get/2` helper that isn't exercised.

**Tests:**
- `apps/data_collector/test/kraken/normalize_test.exs` — every `Normalize` function against canned
  fixtures copied verbatim from verified notes §2/§4 (the `AddOrder`, `OpenOrders`, `BalanceEx`,
  `CancelOrder` REST examples; the `ticker`/`executions` WS examples). Cover: `order_status/3`'s
  `open`+`vol_exec>0`→`PARTIALLY_FILLED` derivation explicitly (this is the trickiest rule in the
  whole adapter per the notes); `ws_order_status/1` vs `order_status/3` being genuinely different
  mappings (assert they diverge on `"partially_filled"` existing only in the WS enum); the
  `order_response_from_placement/2` "NEW + executedQty 0" contract; `account_response/1`'s
  `free = balance - hold_trade` arithmetic on the notes' own worked numbers
  (`balance: 25435.21, hold_trade: 8249.76` → `free: "17185.45"`).
- No `kraken_client_test.exs` — `KrakenClient` itself does HTTP and is intentionally not unit-tested
  directly (matches the OKX adapter's precedent: only `OKX.Normalize`/`OKX.Auth`/`OKX.Symbols` have
  dedicated test files, `OKXClient` does not). All its logic beyond HTTP plumbing lives in
  `Normalize`, which is fully covered above.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test/kraken`

---

### Task 3 — Kraken WebSockets (public ticker + private executions)

**Files:**
- `apps/data_collector/lib/data_collector/kraken_public_stream.ex` (new)
- `apps/data_collector/lib/data_collector/kraken_private_stream.ex` (new)
- `apps/data_collector/lib/data_collector/kraken_private_supervisor.ex` (new)
- `apps/data_collector/lib/data_collector/application.ex` (register the new Registry + DynamicSupervisor)
- `apps/data_collector/lib/data_collector/market_stream.ex` (add `"kraken"` clauses)

First read `okx_public_stream.ex`/`okx_private_stream.ex`/`okx_private_supervisor.ex` again for the
WebSockex reconnect/backoff conventions (`Config.websocket/1`, `calculate_backoff/1`, the
decode-error-counter pattern) — copy them verbatim; only the wire-protocol specifics below differ.

**`DataCollector.KrakenPublicStream`** — single shared connection (like `OKXPublicStream`, unlike
per-symbol `TickerStream`), URL `Application.get_env(:data_collector, :kraken, []) |>
Keyword.get(:ws_url, "wss://ws.kraken.com/v2")`. `subscribe/1`/`unsubscribe/1` mirror
`OKXPublicStream`'s reference-counted `{:ok, count}` contract exactly, backed by a new
`:kraken_public_subscribers` public named ETS table (add its `:ets.new/2` call next to
`:okx_public_subscribers` in `application.ex`).

Frame shapes differ from OKX's `{"op":..., "args":[...]}`:
```elixir
# subscribe
%{method: "subscribe", params: %{channel: "ticker", symbol: [ws_symbol]}}
# unsubscribe
%{method: "unsubscribe", params: %{channel: "ticker", symbol: [ws_symbol]}}
```
`ws_symbol` via `Kraken.Symbols.to_ws_symbol/1` (concat input). On `handle_connect/2`, same
`send(self(), :resubscribe)` pattern as OKX (Kraken doesn't preserve subscriptions across
reconnects either — treat it the same way defensively even though the notes don't explicitly say
so, since no doc claims otherwise and the OKX precedent is the safe default). Ping keepalive: send
`Jason.encode!(%{method: "ping", req_id: ...})` (not the bare `"ping"` string OKX uses — Kraken's
app-level ping is a JSON object per verified notes §4) every `@ping_interval_ms` (reuse OKX's
`20_000`); the expected `{"method":"pong",...}` reply and Kraken's automatic `{"channel":"heartbeat"}`
pushes are both just logged at `:debug` and otherwise ignored (they're liveness signals, not data —
verified notes §4 explicitly flags there's no documented hard disconnect-timeout, so this
send-a-ping-if-quiet behavior is the recommended defensive pattern, not a strict protocol
requirement).

Ticker push routing: `%{"channel" => "ticker", "type" => _, "data" => items}` → `Enum.each(items,
&broadcast_ticker/1)`; `broadcast_ticker/1` reads `item["symbol"]` (already `"BTC/USD"` form),
converts to concat via a **pure string op** (`String.replace(symbol, "/", "")`) — **no**
`Kraken.Symbols` lookup on the incoming path (verified notes §3: WS v2 already speaks `BTC`
natively, no `XBT`/`XDG` substitution needed here, unlike the outgoing `subscribe` path which does
need `Symbols.to_ws_symbol/1` to know where to insert the `/`). Broadcasts
`{:ticker, Normalize.ticker_event(item, concat)}` to `"market:#{concat}"`.

**`DataCollector.KrakenPrivateSupervisor`** — `DynamicSupervisor`, identical shape to
`OKXPrivateSupervisor` (one-for-one). Pair with a new `DataCollector.KrakenPrivateRegistry` Registry
(add both to `application.ex`'s children list, same as the OKX pair).

**`DataCollector.KrakenPrivateStream`** — one connection per account, `ensure_started(account_id,
credentials)` idempotent via `Registry.lookup(DataCollector.KrakenPrivateRegistry, account_id)` then
`DynamicSupervisor.start_child/2`, identical shape to `OKXPrivateStream.ensure_started/2`.

Auth flow differs from OKX's inline WS-login-op: Kraken requires a **REST call first** to mint a
token (`POST /0/private/GetWebSocketsToken`, verified notes §4), then passes that token in the
`subscribe` frame — there is no separate WS-level login op. Expose a small helper on
`DataCollector.KrakenClient` for this (it reuses the exact same private-REST plumbing as every other
private call, just with an empty extra-params body):
```elixir
@spec get_ws_token(ExchangeClient.credentials()) :: {:ok, String.t()} | {:error, term()}
def get_ws_token(credentials)
```
`KrakenPrivateStream.handle_connect/2` calls `KrakenClient.get_ws_token(state.credentials)`
synchronously-via-message (`send(self(), :fetch_token_and_subscribe)`, same async-kickoff pattern
OKX uses for `:do_login`), then on success sends:
```elixir
%{method: "subscribe", params: %{channel: "executions", token: token, snap_orders: true, snap_trades: false}}
```
`snap_orders: true` requests an open-orders snapshot on (re)subscribe — useful for reconciling state
after a reconnect, matching `Trader`'s own recovery-on-restart philosophy; `snap_trades: false`
avoids an unnecessary trade-history flood we don't consume.

**Token refresh** (verified notes §4 — genuinely contradictory docs, resolved conservatively):
schedule a refresh timer (`Process.send_after(self(), :refresh_token, 10 * 60 * 1000)`, i.e. every
10 minutes, comfortably inside the documented 15-minute `expires: 900`), which re-fetches a token
and re-sends the same `subscribe` frame with the new token (Kraken's `subscribe` on an already-
subscribed channel with a fresh token is treated as a resubscribe/reauth, not an error — if this
assumption ever proves wrong in practice, the fallback below still recovers). Also treat any
subscription-status push containing `"Token is expired"` in an `"errorMessage"` field (per verified
notes §4) as an immediate trigger to re-fetch-and-resubscribe, same defensive belt-and-suspenders
approach the notes recommend. **Never log the token itself** — only log that a refresh happened and
whether it succeeded.

Execution push routing: `%{"channel" => "executions", "type" => _, "data" => items}` →
`Enum.each(items, &broadcast_execution_report(&1, state.account_id))`; symbol conversion is again a
pure `String.replace(symbol, "/", "")` (no `Kraken.Symbols` call — same reasoning as the ticker
path). Broadcasts `{:execution_report, Normalize.execution_report(item, concat)}` to
`"order_updates"`. Never log `state.credentials` or the WS token in any `Logger` call in this
module — only `account_id` and Kraken's own non-secret event/error payloads (mirrors
`OKXPrivateStream`'s existing credential-safety comment).

**`DataCollector.MarketStream`** additions:
```elixir
def subscribe("kraken", concat_symbol), do: DataCollector.KrakenPublicStream.subscribe(concat_symbol)
def unsubscribe("kraken", concat_symbol), do: DataCollector.KrakenPublicStream.unsubscribe(concat_symbol)
```
(inserted alongside the existing `"okx"` clauses, before the catch-all `other` clauses).

**Tests:** WS wire-format/routing logic is exercised indirectly through `Normalize`'s already-
comprehensive fixture tests from Task 2 (the pure `ticker_event/2`/`execution_report/2` functions
are what actually transform the payloads — the WebSockex modules are thin routing/reconnect
plumbing around them, matching the OKX adapter's own test-coverage boundary, which has no
`okx_public_stream_test.exs`/`okx_private_stream_test.exs` either). No new test files required for
this task; run the full existing suite to confirm nothing broke from the `application.ex` /
`market_stream.ex` edits.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test`

---

### Task 4 — Enable Kraken end-to-end (registry, UI, Trader wiring)

**Files:**
- `apps/data_collector/lib/data_collector/exchange_registry.ex`
- `apps/shared_data/lib/shared_data/schemas/api_credential.ex`
- `apps/dashboard_web/lib/dashboard_web/forms/account_form.ex`
- `apps/dashboard_web/lib/dashboard_web/live/settings_live.ex`
- `apps/trading_engine/lib/trading_engine/trader.ex`

**`ExchangeRegistry`**: add `def client_for("kraken"), do: {:ok, DataCollector.KrakenClient}` above
the catch-all clause. Update `apps/data_collector/test/exchange_registry_test.exs`: kraken now
resolves ok; `coinbase` still errors until Part B lands (keep both assertions in the same test file,
add kraken's, leave/extend coinbase's as still-unsupported for now — Task 8 flips it).

**`ApiCredential`**: `@supported_exchanges ["binance", "okx", "kraken"]`. No schema/migration
changes needed (`passphrase` is already nullable; Kraken credentials are simply created with it
`nil`). Update `apps/shared_data/test/schemas/api_credential_test.exs`: a `kraken` credential
without a passphrase is now valid (mirrors the existing `binance`-no-passphrase case, **not** the
`okx`-requires-passphrase case).

**`AccountForm`**: `@supported_exchanges ["binance", "okx", "kraken"]` in both places it's checked
(`changeset/2`'s `validate_inclusion`). Kraken must **not** trigger
`validate_passphrase_required_for_okx/1`'s requirement — that private function already only fires
`when get_field(changeset, :exchange) == "okx"`, so no change needed there; just widening
`@supported_exchanges` is sufficient. Update `apps/dashboard_web/test/forms/account_form_test.exs`:
a Kraken exchange value passes validation without a passphrase.

**`settings_live.ex`**: remove `disabled` and the "(coming soon)" label text from the `kraken`
`<option>` (leave `coinbase`'s untouched until Task 8). The existing passphrase-field conditional
block (`<%= if @account_form[:exchange].value == "okx" do %>`) already correctly excludes Kraken —
no change needed to that block. `credential_params`/`credential_updates` already always pass
`"passphrase" => params["passphrase"]`/conditionally include it — for a Kraken submission this value
is simply `nil`/absent and the changeset already tolerates that (`passphrase` isn't in
`validate_required`). No LiveView test changes needed beyond confirming existing tests (none
currently assert on the disabled attribute for kraken specifically — grep to confirm before
skipping).

**`Trader`**: add a `exchange == "kraken"` branch next to the existing `exchange == "okx"` branch in
`init/1` (trader.ex:107-109) that calls `DataCollector.KrakenPrivateStream.ensure_started(account_id,
credentials)` when `requirements.executions` is true — identical shape/condition to the OKX branch,
just naming the sibling module.

**Tests:** extend `exchange_registry_test.exs`, `api_credential_test.exs`, `account_form_test.exs`
as described above. Run the full suite (this task's changes are wiring-only, high risk of a missed
call site — grep for every remaining `"okx"` string literal in the touched files to confirm each
has a Kraken sibling where one is expected).

**Verify:** `MIX_ENV=test mix test`

---

## PART B — Coinbase adapter

### Task 5 — Coinbase `jose` dep, config, Auth (ES256 JWT), Products

**Files:**
- `apps/data_collector/mix.exs` (add `{:jose, "~> 1.11"}`)
- `apps/data_collector/lib/data_collector/coinbase/auth.ex` (new)
- `apps/data_collector/lib/data_collector/coinbase/products.ex` (new)
- `apps/data_collector/lib/data_collector/application.ex` (add `:coinbase_products_cache`-adjacent
  wiring only if Products needs a subscriber-counting table — it does not; Products is lookup-only
  like `OKX.Symbols`, no ETS table needed in `application.ex` beyond what the GenServer itself
  creates in its own `init/1`)
- `config/runtime.exs`, `config/dev.exs`, `config/test.exs` (add `config :data_collector, :coinbase, ...`)
- `.env.example` (add `COINBASE_API_KEY_NAME`/`COINBASE_EC_PRIVATE_KEY_PEM` placeholders)

**mix.exs**: add `{:jose, "~> 1.11"}` to `deps()` in `apps/data_collector/mix.exs`. Per the scout's
own verified findings (coinbase-api-verified.md §1), `jose` is **already locked at exactly
`1.11.12`** transitively (via `ueberauth_apple`) and is already compiled in `_build/{dev,test}`.
Adding this declaration should not change resolution. **After adding the line, run `git diff
mix.lock`** — it must be byte-empty. If it is not empty, **stop and report** instead of proceeding
(per the env rule against `mix.lock`-mutating actions) — do not run `mix deps.get` to "fix" it.

**Config**:
```elixir
config :data_collector, :coinbase,
  base_url: System.get_env("COINBASE_BASE_URL", "https://api.coinbase.com"),
  ws_public_url: System.get_env("COINBASE_WS_PUBLIC_URL", "wss://advanced-trade-ws.coinbase.com"),
  ws_user_url: System.get_env("COINBASE_WS_USER_URL", "wss://advanced-trade-ws-user.coinbase.com")
```
`config/test.exs` gets fixed mock values, same pattern as Kraken/OKX. No demo/sandbox flag in this
config block — the sandbox host (`api-sandbox.coinbase.com`) is a manual-E2E-only concern (Part D),
never selected by app config, since it returns static/input-ignoring responses unsuitable for any
real usage path (verified notes §5).

**Credentials mapping, spelled out explicitly (this is the one place Coinbase's credential shape
differs semantically from every other adapter, even though the Elixir *type* is unchanged):**
`credentials.api_key` holds Coinbase's **key name** string, shaped
`organizations/{org_id}/apiKeys/{key_id}` (used as both the JWT `kid` header and `sub` claim — it is
not a secret, but do not log it either, out of general caution). `credentials.secret_key` holds the
**EC private key PEM** (`-----BEGIN EC PRIVATE KEY-----...`), stored in the *same*
`SharedData.Encrypted.Binary` field every other adapter uses for its `secret_key` — Cloak encrypts
arbitrary binaries including multi-line PEM text with embedded newlines with zero changes needed to
the schema or the encryption module (verify this assumption in Task 8's test by round-tripping a
multi-line fixture PEM through an `ApiCredential` insert/reload). `credentials.passphrase` is always
`nil`.

**`DataCollector.Coinbase.Auth`**:
```elixir
@spec build_jwt(ExchangeClient.credentials(), method :: String.t(), path :: String.t()) :: String.t()
def build_jwt(%{api_key: key_name, secret_key: pem}, method, path) do
  jwk = JOSE.JWK.from_pem(pem)
  now = System.system_time(:second)
  header = %{"alg" => "ES256", "typ" => "JWT", "kid" => key_name, "nonce" => random_nonce()}
  claims = %{
    "sub" => key_name, "iss" => "cdp", "nbf" => now, "exp" => now + 120,
    "uri" => "#{String.upcase(method)} api.coinbase.com#{path}"
  }
  {_, compact} = JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact()
  compact
end

@spec build_ws_jwt(ExchangeClient.credentials()) :: String.t()
def build_ws_jwt(%{api_key: key_name, secret_key: pem}) do
  # identical to build_jwt/3 but with NO "uri" claim in `claims` (verified notes §1: build_ws_jwt
  # omits it entirely — do not pass an empty string, omit the key)
end

defp random_nonce, do: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
```
`Authorization` header on every REST call: `"Bearer " <> build_jwt(credentials, method, path)`.
**No `aud` claim** — the scout explicitly cross-checked this against Coinbase's own actively-
maintained SDK source (higher-confidence than a generic docs page that claimed otherwise) and
recorded the ambiguity; follow the SDK's actual behavior, omit `aud`.

**Tests** (`apps/data_collector/test/coinbase/auth_test.exs`) — network-free, credential-free
round-trip, mirroring the scout's own verification method exactly:
1. Generate a throwaway P-256 key: `JOSE.JWK.generate_key({:ec, :secp256r1})`.
2. Build a JWT via `build_jwt/3` using that key's PEM (via `JOSE.JWK.to_pem/1`) as
   `credentials.secret_key`.
3. `JOSE.JWT.verify(JOSE.JWK.to_public(jwk), compact_jwt)` and assert `verified? == true`.
4. Decode the header and claims and assert every field matches the spec above exactly (`alg`,
   `typ`, `kid`, presence of `nonce`; `sub`, `iss`, `nbf`/`exp` 120s apart, `uri` format
   `"POST api.coinbase.com/api/v3/brokerage/orders"` with no `aud` key present in the claims map).
5. Repeat with a **static, fixture, non-real** SEC1 PEM (embed the exact fake key from
   coinbase-api-verified.md §1 "Check 2" — it was generated purely for scouting, never a live
   credential) to prove `JOSE.JWK.from_pem/1` handles Coinbase's exact SEC1 shape with zero
   conversion, matching the scout's own proof.
6. `build_ws_jwt/1` — assert the resulting decoded claims map has no `"uri"` key at all (not an
   empty string).

**`DataCollector.Coinbase.Products`** — GenServer + public ETS, same lazy-load pattern as
`OKX.Symbols`/`Kraken.Symbols`, sourced from the **public, unauthenticated**
`GET /api/v3/brokerage/market/products?product_type=SPOT` (the `market/`-prefixed mirror — verified
notes §3, avoids burning any private JWT/rate-limit budget for pure market-data reads; paginate on
`has_next`/`cursor` the same way `KrakenClient.get_account/1`-adjacent code doesn't need to, but
`Products`'s own fetch loop does — implement a simple `fetch_all_pages/1` accumulator). Public API:

- `to_product_id/1` (concat → `product_id`, e.g. `"BTCUSD"` → `"BTC-USD"`)
- `to_concat/1` (`product_id` → concat)
- `product_info/1` (concat → `%{base_increment: String.t(), quote_increment: String.t(),
  base_min_size: String.t()}`)

Mapping recipe (verified notes §3): concat ↔ `product_id` is a straight
`String.replace(product_id, "-", "")` / hyphen-insert-at-base/quote-boundary — **no legacy-ticker
substitution table needed** (unlike Kraken's `XBT`/`XDG` — Coinbase uses plain current tickers
throughout), so building the reverse map is simpler: cache `{concat, product_id, info}` triples
directly from each product's own `product_id`/`base_currency_id`/`quote_currency_id` fields (concat
= `base_currency_id <> quote_currency_id`), filtering `status == "online"`.

**No special-casing for the USDT-quote caveat belongs in this module.** The scout's finding (only 23
of 925 SPOT products are USDT-quoted, and those are likely unavailable to EU/EEA accounts post-MiCA)
is a **coverage fact about which concat symbols will resolve**, not an ambiguity in the mapping
*function* itself — each `product_id` maps to exactly one concat symbol by construction, so there is
no multi-candidate resolution logic to write. A `"XXXUSDT"` concat symbol simply returns
`{:error, :unknown_symbol}` like any other symbol Coinbase doesn't list, which is already the
correct, honest behavior. Document the caveat instead as an **operational note for users choosing
which pairs to trade** — this belongs in Part D's E2E checklist, not in adapter code.

**Tests** (`apps/data_collector/test/coinbase_products_test.exs`) — pure parsing tests against a
canned `products` list fixture (use the live-verified `BTC-USD` field example from verified notes
§2's Products section, plus a second product to prove multi-entry parsing, plus one `status !=
"online"` entry to prove filtering). Assert `to_product_id/1`, `to_concat/1`, `product_info/1`, and
`{:error, :unknown_symbol}` for an unlisted concat.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test/coinbase apps/data_collector/test/coinbase_products_test.exs && git diff mix.lock` (must show no output)

---

### Task 6 — Coinbase Normalize + CoinbaseClient (REST)

**Files:**
- `apps/data_collector/lib/data_collector/coinbase/normalize.ex` (new)
- `apps/data_collector/lib/data_collector/coinbase_client.ex` (new)

**`DataCollector.Coinbase.Normalize`** — pure functions, mirrors `OKX.Normalize`'s shape:

- `order_status/3` — `(status :: String.t(), filled_size :: String.t(), order_size :: String.t())
  :: String.t()`. `"PENDING"`/`"QUEUED"`/`"CANCEL_QUEUED"`/`"EDIT_QUEUED"` → `"NEW"`; `"OPEN"` with
  `Decimal.new(filled_size) |> Decimal.gt?(Decimal.new(0))` and `Decimal.lt?(Decimal.new(filled_size),
  Decimal.new(order_size))` → `"PARTIALLY_FILLED"`; `"OPEN"` otherwise → `"NEW"`; `"FILLED"` →
  `"FILLED"`; `"CANCELLED"` (double-L, Coinbase's own spelling — pattern-match it exactly, do not
  write the single-L American spelling on the *input* side) → `"CANCELED"`; `"EXPIRED"` →
  `"CANCELED"`; `"FAILED"` → `"CANCELED"`; `"UNKNOWN_ORDER_STATUS"`/anything else → log
  `Logger.warning/1` and pass through upcased.
- `order_configuration/1` — Binance-format `order_params` → Coinbase's `order_configuration` body
  fragment. `"MARKET"` →
  `%{market_market_ioc: %{base_size: to_string(order_params.quantity)}}`; `"LIMIT"` →
  `%{limit_limit_gtc: %{base_size: to_string(order_params.quantity), limit_price:
  to_string(order_params.price), post_only: false}}`. Always uses `base_size` (never `quote_size`) —
  matches Binance's `quantity` semantics with no analog to OKX's `tgtCcy`/Kraken's `viqc` gotcha,
  since Coinbase's `base_size` is unconditionally base-currency-denominated for both order types
  (verified notes §2 — call this out as the third and simplest of the three adapters on this exact
  point).
- `order_request/2` — `(order_params, product_id)` →
  ```elixir
  %{
    client_order_id: order_params[:client_order_id] || generate_client_order_id(),
    product_id: product_id,
    side: String.upcase(order_params.side),
    order_configuration: order_configuration(order_params)
  }
  ```
  `generate_client_order_id/0` (private) uses `Ecto.UUID.generate/0` (already an umbrella dep via
  Ecto) — **never** send an empty string (verified notes §2: empty auto-generates server-side but
  forfeits the duplicate-order safeguard; always send our own so retries/reconciliation can use it).
- `order_response/2` — `(order_details_response :: map(), concat_symbol :: String.t())` → Binance-
  shaped order map, reading the `GET /orders/historical/{order_id}` response shape (verified notes
  §2): `"orderId"` ← `order_id`, `"clientOrderId"` ← `client_order_id`, `"symbol"` ← `concat_symbol`,
  `"type"` ← `String.upcase(order_type)`, `"side"` ← `String.upcase(side)`, `"price"` ← limit orders'
  `limit_price` from the echoed `order_configuration` (pattern-match
  `order_configuration.limit_limit_gtc.limit_price`) **or**, for market orders with no limit_price,
  `average_filled_price` (may be `nil`/`"0"` pre-fill — pass through as-is, downstream code already
  tolerates a nil/zero price for unfilled market orders the same way it does for OKX), `"origQty"` ←
  the echoed config's `base_size` (or `quote_size` if that's what was actually sent — read whichever
  key is present in the echoed `order_configuration`), `"executedQty"` ← `filled_size`, `"status"`
  ← `order_status/3` fed `status`/`filled_size`/`origQty`, `"timeInForce"` ← `"GTC"` (this app never
  places `market_market_ioc` with a different TIF semantic worth surfacing — hardcode, matching the
  OKX/Kraken adapters' own hardcoded `"GTC"` fallback).
- `cancel_response/2` — a single `batch_cancel` `results[]` entry + concat symbol →
  `{:ok, %{"orderId" => order_id, "status" => "CANCELED", "symbol" => concat_symbol}}` when
  `success == true`; `{:error, failure_reason}` when `success == false` (returns a result tuple,
  not a bare map, since failure is a normal per-order outcome on this batch endpoint — the caller
  in `CoinbaseClient.cancel_order/3` unwraps it).
- `account_response/1` — a **flattened, already-fully-paginated** `accounts` list →
  `%{"balances" => [%{"asset" => currency, "free" => available_balance_value, "locked" =>
  hold_value}]}`, reading `currency`, `available_balance.value`, `hold.value` per account entry
  (verified notes §2's live-confirmed sandbox example). Pagination itself is `CoinbaseClient`'s job
  (loop on `has_next`/`cursor`, accumulate `accounts` across pages, pass the full flattened list into
  this pure function once).
- `exchange_info/2` — `(product_info, concat_symbol)` → same shape as OKX/Kraken's `exchange_info/2`
  (`PRICE_FILTER`/`tickSize` ← `quote_increment`, `LOT_SIZE`/`stepSize`+`minQty` ← `base_increment`/
  `base_min_size`).
- `ticker_event/2` — a single `events[].tickers[]` item + concat symbol →
  `%{"e" => "24hrTicker", "s" => concat, "c" => price, "o" => nil, "h" => high_24_h, "l" => low_24_h,
  "v" => volume_24_h, "q" => nil}` (reads Coinbase's own field names `price`, `high_24_h`,
  `low_24_h`, `volume_24_h` — all already strings per the verified example, no `to_string` wrapping
  needed here unlike Kraken's numeric WS ticker fields).
- `execution_report/3` — `(order_item, concat_symbol, prev_cum_qty :: Decimal.t())` → Binance-shaped
  executionReport. **This is the adapter's one genuinely thinner payload** (verified notes §4 —
  Coinbase's `user` channel doesn't send a per-fill delta or an original order size the way OKX/
  Kraken do):
  ```elixir
  cum_qty = Decimal.new(order_item["cumulative_quantity"])
  last_qty = Decimal.sub(cum_qty, prev_cum_qty)
  leaves_qty = Decimal.new(order_item["leaves_quantity"])
  order_qty = Decimal.add(cum_qty, leaves_qty)   # derived: cum + remaining = original size

  %{
    "e" => "executionReport",
    "i" => order_item["order_id"],
    "s" => concat_symbol,
    "S" => String.upcase(order_item["order_side"]),   # NOT order_item["side"] — the WS `user`
                                                        # channel names this field differently from
                                                        # every REST endpoint (verified notes §4) —
                                                        # this is a documented easy-cross-wiring trap.
    "X" => order_status(order_item["status"], order_item["cumulative_quantity"], Decimal.to_string(order_qty)),
    "x" => ws_exec_type(order_item["status"], last_qty),
    "l" => Decimal.to_string(last_qty),
    "L" => order_item["avg_price"],   # approximation, NOT a true last-fill price — Coinbase sends
                                       # no such field on this channel (verified notes §4); flagged
                                       # explicitly here and in the moduledoc, not a silent guess.
    "z" => order_item["cumulative_quantity"],
    "q" => Decimal.to_string(order_qty)
  }
  ```
  `ws_exec_type/2` (private helper): `status == "FILLED"` or (`status == "OPEN"` and
  `Decimal.gt?(last_qty, Decimal.new(0))`) → `"TRADE"`; `status == "OPEN"` and
  `Decimal.eq?(last_qty, Decimal.new(0))` → `"NEW"`; `status` in
  `~w(CANCELLED EXPIRED FAILED)` → `"CANCELED"`; else upcase-passthrough.
  `prev_cum_qty` is supplied by `CoinbasePrivateStream` (Task 7), which keeps a small
  `%{order_id => Decimal.t()}` map in its own process state, seeded to `Decimal.new(0)` the first
  time an order_id is seen (including right after any reconnect — the moduledoc must say plainly
  that a reconnect resets this tracking, so the very first execution report seen post-reconnect for
  an in-flight order will (mildly inaccurately) report `"l"` as the *entire* cumulative fill rather
  than a true delta; this is the same class of documented, honest limitation the verified notes
  flag, not a bug to silently paper over).

**`DataCollector.CoinbaseClient`** (`@behaviour DataCollector.ExchangeClient`):

- `get_account/1`: loop `GET /api/v3/brokerage/accounts?cursor=...` accumulating `accounts` across
  pages until `has_next == false`, then `Normalize.account_response/1`.
- `create_order/2`: `Products.to_product_id/1` → `Normalize.order_request/2` →
  `POST /api/v3/brokerage/orders`. On `%{"success" => true, "success_response" => %{"order_id" =>
  order_id}}`, **must** do a follow-up `GET /api/v3/brokerage/orders/historical/{order_id}` (the
  create-order response deliberately excludes price/qty/status per verified notes §2 — this is the
  one adapter of the three where the "GET after placing" pattern OKX pioneered is unambiguously
  required, not optional) → `Normalize.order_response/2`. On `%{"success" => false,
  "error_response" => %{"new_order_failure_reason" => reason, "message" => msg}}` →
  `{:error, "Coinbase order rejected (#{reason}): #{msg}"}` (branch on `new_order_failure_reason`,
  not the deprecated `error` field, per verified notes §2). **Important**: Coinbase's error response
  can arrive with **HTTP 200** — never assume a 2xx status code alone means success; always check
  the `"success"` boolean field first.
- `cancel_order/3`: `POST /api/v3/brokerage/orders/batch_cancel` with `%{order_ids: [order_id]}` →
  take `results` list's single entry → `Normalize.cancel_response/2` (already returns a result
  tuple, pass it through).
- `get_open_orders/2`: `GET /api/v3/brokerage/orders/historical/batch?order_status=OPEN[&product_id=...]`
  (product_id filter only added when `symbol` is non-nil, resolved via `Products.to_product_id/1`)
  → map each `orders[]` entry (already carries enough fields to normalize directly — verified notes
  §2's List Orders example — no additional per-order GET needed here, unlike `create_order/2`) via
  `Normalize.order_response/2`.
- `get_exchange_info/1`: `Products.product_info/1` → `Normalize.exchange_info/2`. No HTTP call.

**Request plumbing**: `Coinbase.Auth.build_jwt(credentials, method, path)` → `Authorization: Bearer
<jwt>` header, `Content-Type: application/json` for POST bodies, wrapped in
`DataCollector.CircuitBreaker.call(:coinbase_api, fn -> ... end)`. Decode envelope: for the generic
`grpc.gateway.runtime.Error` shape (`%{"error" => _, "code" => _, "message" => _}`, non-order-
specific failures like auth errors) → `{:error, message}`; for order-specific `success: false` →
handled explicitly in `create_order/2`/`cancel_order/3` above, not in the generic envelope decoder
(those endpoints return `200` with a `success` boolean, not a `code`/`error` pair).

**Tests** (`apps/data_collector/test/coinbase/normalize_test.exs`) — every `Normalize` function
against canned fixtures copied verbatim from verified notes §2/§4 (Create Order example, Get Order
shape, List Orders, batch_cancel, the live sandbox Accounts example, the live Products example, the
`ticker`/`user` WS canonical examples). Cover explicitly: the `order_side` vs `side` field-name trap
(assert a fixture using only `order_side` normalizes correctly, and that a fixture with a
conflicting/absent `side` key doesn't accidentally get read); the `cumulative_quantity`-delta
derivation across two sequential calls with different `prev_cum_qty` inputs; the `leaves_quantity +
cumulative_quantity = orig_qty` derivation; `"CANCELLED"` (double-L) input → `"CANCELED"` (single-L)
output.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test/coinbase`

---

### Task 7 — Coinbase WebSockets (public ticker + private user)

**Files:**
- `apps/data_collector/lib/data_collector/coinbase_public_stream.ex` (new)
- `apps/data_collector/lib/data_collector/coinbase_private_stream.ex` (new)
- `apps/data_collector/lib/data_collector/coinbase_private_supervisor.ex` (new)
- `apps/data_collector/lib/data_collector/application.ex` (register new Registry + DynamicSupervisor
  + `:coinbase_public_subscribers` ETS table)
- `apps/data_collector/lib/data_collector/market_stream.ex` (add `"coinbase"` clauses)

**`DataCollector.CoinbasePublicStream`** — single shared connection to
`Application.get_env(:data_collector, :coinbase, []) |> Keyword.get(:ws_public_url, "wss://advanced-trade-ws.coinbase.com")`.
Same reference-counted `subscribe/1`/`unsubscribe/1` contract as Kraken/OKX's public streams,
backed by a new `:coinbase_public_subscribers` ETS table. **Requires no credentials at all** — the
`ticker` channel doesn't strictly need a `jwt` field (verified notes §4); omit the `jwt` key from
outgoing subscribe frames for this module entirely rather than threading a fake/empty credential
through it.

```elixir
%{type: "subscribe", product_ids: [product_id], channel: "ticker"}
```
**Must subscribe within 5 seconds of connecting** (verified notes §4 — the hardest deadline of the
three adapters; OKX/Kraken tolerate much longer idle windows) — send the subscribe frame
synchronously from `handle_connect/2` for any symbols with existing subscribers (same
`:resubscribe`-on-connect pattern as Kraken/OKX, but dispatched immediately rather than via
`send(self(), :resubscribe)` + a subsequent message-queue hop, to comfortably clear the 5s window
under load; if the implementer keeps the message-hop pattern for consistency with the other two
adapters, they must confirm empirically/by code-reading that it still reliably lands well under 5s).
Also subscribe to the `heartbeats` channel at connect (`%{type: "subscribe", channel: "heartbeats"}`,
no `product_ids` needed) — Coinbase's heartbeat is a **push-based** keepalive that only flows once
you're subscribed to it (verified notes §4), unlike OKX/Kraken's client-initiated ping — so this
module sends **no** app-level ping frames of its own; `handle_frame/2` for `%{"channel" =>
"heartbeats"}` just logs at `:debug`.

Ticker routing: `%{"channel" => "ticker", "events" => events}` → the envelope is nested **two
levels deep** (`events[].tickers[]`, not a flat `data[]` array like OKX/Kraken — verified notes §4,
explicit trap) — `Enum.flat_map(events, & &1["tickers"]) |> Enum.each(&broadcast_ticker/1)`.
`broadcast_ticker/1` reads `item["product_id"]`, resolves concat via
`Coinbase.Products.to_concat/1` (an actual lookup this time, unlike Kraken's WS path — Coinbase's
`product_id` always needs the hyphen-stripped translation and there's no "WS already speaks the
right dialect" shortcut here).

**`DataCollector.CoinbasePrivateSupervisor`** — `DynamicSupervisor`, identical shape to
`OKXPrivateSupervisor`/`KrakenPrivateSupervisor`. Pair with `DataCollector.CoinbasePrivateRegistry`.

**`DataCollector.CoinbasePrivateStream`** — one per account, connects to
`Keyword.get(config, :ws_user_url, "wss://advanced-trade-ws-user.coinbase.com")`. State carries
`credentials`, `account_id`, and `last_cum_qty :: %{order_id => Decimal.t()}` (see Task 6's
`execution_report/3`). On connect, subscribes the `user` channel **with a freshly-minted JWT built
right before sending** (`Coinbase.Auth.build_ws_jwt/1`, never cached/reused across sends — verified
notes §4's per-message-JWT requirement):
```elixir
%{type: "subscribe", product_ids: [], channel: "user", jwt: Coinbase.Auth.build_ws_jwt(credentials)}
```
(`product_ids: []` subscribes to all products for the account — verified notes §4's canonical
example doesn't scope `user` by product). Also subscribes to `heartbeats` on this connection too
(same reasoning as the public stream — keeps the private connection alive without a client ping).

Order-event routing: `%{"channel" => "user", "events" => events}` →
`Enum.flat_map(events, & &1["orders"]) |> Enum.each(&broadcast_execution_report(&1, state))`.
`broadcast_execution_report/2` resolves concat via `Coinbase.Products.to_concat/1` on
`item["product_id"]`, looks up `prev_cum_qty = Map.get(state.last_cum_qty, item["order_id"],
Decimal.new(0))`, calls `Normalize.execution_report/3`, updates
`state.last_cum_qty[item["order_id"]] = Decimal.new(item["cumulative_quantity"])`, broadcasts
`{:execution_report, report}` to `"order_updates"`. On reconnect, `last_cum_qty` resets to `%{}`
(new process state) — document this in the moduledoc as the accepted, honest limitation from Task 6.
Never log `credentials`, the built JWT, or `state.last_cum_qty`'s keys/values in a way that could
leak order sizes at more than `:debug` — actually order sizes aren't secrets, only the credential
material and JWTs are; the hard rule is specifically about api keys/secrets/PEM/JWTs/tokens, not
trade sizes.

Reconnect/backoff: same `handle_disconnect/2` shape as Kraken/OKX (`Config.websocket/1`-driven
backoff), with `last_cum_qty` reset to `%{}` on reconnect and a fresh JWT minted for the
resubscribe (never reuse a JWT across connections — it may already be near/past its 2-minute expiry).

**`DataCollector.MarketStream`** additions:
```elixir
def subscribe("coinbase", concat_symbol), do: DataCollector.CoinbasePublicStream.subscribe(concat_symbol)
def unsubscribe("coinbase", concat_symbol), do: DataCollector.CoinbasePublicStream.unsubscribe(concat_symbol)
```

**Tests:** same boundary as Kraken's Task 3 — the pure `Normalize` functions (already covered in
Task 6) are what's unit-tested; no new WebSockex-level test files, matching the OKX precedent. Run
the full suite to confirm the `application.ex`/`market_stream.ex` wiring compiles and doesn't break
anything.

**Verify:** `MIX_ENV=test mix test apps/data_collector/test`

---

### Task 8 — Enable Coinbase end-to-end (registry, UI, Trader wiring)

**Files:**
- `apps/data_collector/lib/data_collector/exchange_registry.ex`
- `apps/shared_data/lib/shared_data/schemas/api_credential.ex`
- `apps/dashboard_web/lib/dashboard_web/forms/account_form.ex`
- `apps/dashboard_web/lib/dashboard_web/live/settings_live.ex`
- `apps/trading_engine/lib/trading_engine/trader.ex`

**`ExchangeRegistry`**: `def client_for("coinbase"), do: {:ok, DataCollector.CoinbaseClient}`.
Update `exchange_registry_test.exs`.

**`ApiCredential`**: `@supported_exchanges ["binance", "okx", "kraken", "coinbase"]`. No new
migration — `passphrase` stays `nil` for Coinbase; the existing `api_key`/`secret_key` encrypted
fields hold the key name / EC PEM respectively (see Task 5). Add a regression test in
`api_credential_test.exs` proving the **multi-line PEM round-trips correctly through Cloak
encryption** — insert a credential with a fixture `secret_key` containing embedded `\n` characters
(a fake, non-real EC PEM — reuse the same fixture from Task 5's auth tests), reload it from the DB,
assert the decrypted value is byte-identical including newlines. This is the one Coinbase-specific
correctness risk explicitly called out in the task brief ("multi-line-safe").

**`AccountForm`**: `@supported_exchanges ["binance", "okx", "kraken", "coinbase"]`. No new
passphrase-requiredness branch — Coinbase never requires one. Update `account_form_test.exs`.

**`settings_live.ex`**: remove `disabled` + "(coming soon)" from the `coinbase` `<option>`. Relabel
the existing "API Key"/"Secret Key" input fields' **helper text** (not their `name=` attributes —
those stay `account[api_key]`/`account[secret_key]` for schema/form-field consistency across every
exchange) to be exchange-aware: when `@account_form[:exchange].value == "coinbase"`, show
placeholder/label text like "Key Name (organizations/.../apiKeys/...)" for the API Key field and
"EC Private Key (PEM, starts with -----BEGIN EC PRIVATE KEY-----)" for the Secret Key field, using
the same `<%= if @account_form[:exchange].value == "coinbase" do %>` conditional-rendering pattern
already established for OKX's passphrase field. The Secret Key `<input>` must be a `<textarea>` for
Coinbase specifically (a PEM block is multi-line and won't paste/display sanely in a single-line
`<input type="password">`) — conditionally render a `<textarea name="account[secret_key]">` for
Coinbase and keep the existing `<input type="password" name="account[secret_key]">` for every other
exchange, so the submitted param name is identical either way and no controller/LiveView handler
logic needs to branch on exchange.

**`Trader`**: add an `exchange == "coinbase"` branch next to the `"kraken"`/`"okx"` branches in
`init/1`, calling `DataCollector.CoinbasePrivateStream.ensure_started(account_id, credentials)`.

**Tests:** extend all four test files as described. Run the full suite.

**Verify:** `MIX_ENV=test mix test`

---

## PART C — Automation improvements (scout's TOP PICKS, verbatim)

Implements exactly the 5 items ranked in `docs/superpowers/notes/automations-review.md`'s "TOP
PICKS for this round" section — no more, no less. Each was independently verified by the scout via
code trace (not empirically reproduced by crashing a live process, per that review's own stated
method) and is safe, self-contained, and does not change any strategy's trading semantics.

### Task 9 — Zombie-trader fix + subscription-leak fix + position tracking

**Files:**
- `apps/trading_engine/lib/trading_engine/account_supervisor.ex`
- `apps/trading_engine/lib/trading_engine/trader.ex`

**9a. `account_supervisor.ex`: `restart: :transient` → `restart: :temporary`** (automations-review.md
Part B #1, the review's single CRITICAL-severity finding). One-line change on the child-spec's
`restart:` option (currently `account_supervisor.ex:17`). Rationale (from the review, restated for
the implementer): `:transient` children are auto-restarted by the `DynamicSupervisor` on any
abnormal exit, using the original `start_link` args captured in the child-spec closure —
**independently of and invisibly to** `StrategyManager`'s own `Process.monitor`-based bookkeeping,
which reacts to the same crash by deactivating the DB row and forgetting the trader. The net effect
today is a crashed-and-silently-respawned live trading process that the rest of the app (and the
UI's stop button, which routes through `StrategyManager`) believes is stopped. `:temporary` means a
crash simply stays down; `Trader.init/1`'s existing `check_for_recovery/4` path remains the correct,
already-built way to safely resume a strategy, invoked explicitly via `StrategyManager.start_strategy/1`
rather than an invisible supervisor-level auto-restart.

**9b. `trader.ex`: `terminate/2` unsubscribes via the exchange-aware `MarketStream` facade, not the
Binance-only `TickerStream`** (Part B #4, directly relevant to this branch — the bug gets strictly
worse with every exchange added, and this spec adds two). Currently (`trader.ex:360-363`,
approximate — re-locate by searching for `TickerStream.unsubscribe` in the file) the unsubscribe
call on terminate hardcodes `DataCollector.TickerStream.unsubscribe(sym)` regardless of
`state.exchange`, while the matching `subscribe` call in `init/1` already correctly goes through
`DataCollector.MarketStream.subscribe(state.exchange, sym)`. Fix: replace the terminate-time call
with `DataCollector.MarketStream.unsubscribe(state.exchange, sym)` — `MarketStream.unsubscribe/2`
already exists with exactly this signature (extended by Tasks 3 and 7 of this same spec to cover
`"kraken"`/`"coinbase"` too) and is simply never called from `terminate/2` today. Without this fix,
every OKX/Kraken/Coinbase trader stop leaks one dangling public-stream subscription that never
decrements.

**9c. `trader.ex`: populate `state.positions` from fills so `RiskManager.check_position_size/2`
actually enforces the position cap** (Part B #2's self-contained half — the daily-loss half is
explicitly out of scope, it needs a real PnL pipeline per the review's own Future Work section).
`state.positions` (initialized to `%{}` in `init/1`, never reassigned anywhere else in the file
today) must be updated inside the existing `handle_info({:execution_report, execution}, state)`
clause (`trader.ex:250-314`, approximate), using the side/qty already extracted there for the
existing PubSub broadcast. On each execution report this Trader owns (post `owns_execution?/2`
filtering, same ownership check already in place), update `state.positions` to the shape
`RiskManager.calculate_position_size/1` already expects (`%{symbol => %{quantity: Decimal.t()}}` —
confirm the exact key shape by reading `risk_manager.ex:123-128`'s `calculate_position_size/1`
before writing the update logic): on a `BUY` fill, add the newly-filled quantity (the incremental
delta between this execution's `"z"` cumulative-fill and whatever was last recorded for that
`order_id`, **not** the raw `"z"` value itself, to avoid double-counting on repeated
`PARTIALLY_FILLED` pushes for the same order) to the symbol's tracked quantity; on a `SELL` fill,
subtract it. Track per-`order_id` last-seen cumulative qty in Trader state (a small new map,
`state.last_cum_qty_by_order`, reset is not needed since Trader state is per-process and dies with
the order-tracking lifecycle) to compute that delta safely regardless of which exchange the
execution report came from — this works uniformly for Binance/OKX/Kraken/Coinbase since all four
adapters already normalize `"z"` (cumulative fill qty) into the same Binance-shaped key.

**Tests:** extend `apps/trading_engine/test/trading_engine/trader_test.exs` (or wherever the
existing execution-report handling is tested) to assert: (a) a `BUY` execution report updates
`state.positions` upward by the correct delta, not the raw cumulative value, across two sequential
`PARTIALLY_FILLED` pushes for the same order; (b) a `SELL` reduces it; (c)
`RiskManager.check_position_size/2` now actually rejects an order that would exceed the configured
cap (previously impossible to test meaningfully since positions were always `%{}` — this is new
test coverage the review flagged as currently absent). Extend `account_supervisor_test.exs` (or
create one if none exists) to assert the child spec's `restart` value is `:temporary`. No new test
needed for 9b beyond confirming `MarketStream.unsubscribe/2` is called with `state.exchange` — a
`Mox`/manual-stub-based assertion if the codebase already has one for `MarketStream`, otherwise a
direct call-count/argument assertion via whatever mocking convention `trader_test.exs` already uses
for `MarketStream.subscribe/2`'s existing test coverage (mirror that pattern exactly, don't
introduce a new mocking approach).

**Verify:** `MIX_ENV=test mix test apps/trading_engine/test`

### Task 10 — `chains_live.ex` broken "Start Chain" fix + test-env restore guard

**Files:**
- `apps/dashboard_web/lib/dashboard_web/live/chains_live.ex`
- `apps/trading_engine/lib/trading_engine/strategy_manager.ex`
- `config/test.exs`

**10a. `chains_live.ex`: route chain start/stop/cancel through `StrategyManager`** (Part B #3, the
review's other HIGH-severity, directly-broken-today finding). `start_chain_execution/1` currently
calls `TradingEngine.AccountSupervisor.start_trader(account_id, setting_id: setting_id)` — passing
only `setting_id:` in opts, missing the `exchange`/`credentials`/`strategy`/`strategy_config` keys
`Trader.init/1` requires via `Keyword.fetch!`, which raises `KeyError` and fails the `start_child`
call synchronously, while the DB row is left with `is_active: true` regardless (the caller only
surfaces a flash message, doesn't roll back the flag — a second, compounding state-desync bug on
top of the crash). Fix: replace all three call sites (`start_chain_execution/1`,
`stop_chain_execution/1`, `cancel_chain_execution/1`) with
`TradingEngine.StrategyManager.start_strategy/1` / `TradingEngine.StrategyManager.stop_strategy/1`
— the existing, correct, `setting_id`-only-taking public API that already builds full `Trader` opts
(`start_trader_for_setting/1`, private, called internally), registers the crash monitor
(`add_running_trader/3`), and wires `StopConditionsMonitor` registration, none of which
`AccountSupervisor.start_trader/2` called directly does. This also fixes the review's compounding
note: chain-started traders were previously invisible to `StrategyManager.running_traders`/
`get_running_strategies/0`/`is_running?/1` even when the crash was worked around by hand; routing
through `StrategyManager` fixes that for free.

**10b. Gate `StrategyManager`'s `:restore_active_strategies` behind a config flag, `false` in
tests** (Part B #4 / "known issue 2" — a real, verified-by-code-trace mechanism, not yet
empirically triggered but a genuine test-environment hazard). `handle_info(:restore_active_strategies,
...)` (`strategy_manager.ex:137`) is scheduled via `Process.send_after(self(), :restore_active_strategies,
1000)` in `init/1` (line 88) and queries the DB from a process with no Ecto Sandbox checkout once it
fires — both `dashboard_web`'s and `shared_data`'s `test_helper.exs` set `Sandbox.mode(SharedData.Repo,
:manual)`, and `dashboard_web` depends on `trading_engine`, so `StrategyManager` boots in that test
VM too. Fix: wrap the scheduling (not the handler) in a config check —
```elixir
if Application.get_env(:trading_engine, :restore_on_boot, true) do
  Process.send_after(self(), :restore_active_strategies, 1000)
end
```
and add `config :trading_engine, :restore_on_boot, false` to `config/test.exs`, following the
**exact existing precedent already in that same file** for disabling Oban queues/Cron/Pruner under
test for the identical "don't run background jobs against the Sandbox-owned Repo" reason (locate
that block and mirror its comment style).

**Tests:** `chains_live.ex` — extend whatever LiveView test already covers "Start Chain"/"Stop
Chain"/"Cancel Chain" (`apps/dashboard_web/test/dashboard_web_live/chains_live_test.exs` or
equivalent — locate via grep) to assert starting a chain no longer raises/errors and results in a
running trader registered with `StrategyManager.is_running?/1`, and that stopping cleanly
deactivates it. `strategy_manager.ex` — add/extend a unit test asserting `:restore_active_strategies`
is **not** scheduled when `Application.get_env(:trading_engine, :restore_on_boot)` is `false` (spy
on `Process.send_after`/assert no `:restore_active_strategies` message arrives within a short
`assert_receive` refute-window), and that the existing restore behavior still works when the config
is `true` (default, matches current production behavior) — do not weaken the production-path test
coverage while adding the test-path guard.

**Verify:** `MIX_ENV=test mix test apps/dashboard_web/test apps/trading_engine/test`

---

## PART D — Regression & E2E

### Task 11 — Full regression pass + Kraken/Coinbase E2E checklist

**Files:**
- `docs/superpowers/notes/kraken-coinbase-e2e-checklist.md` (new)

No production code changes in this task — verification only, plus the one new doc file.

**Regression checks (run and confirm green/clean before writing the checklist doc):**
1. `MIX_ENV=test mix test` — full suite green, including every test added by Tasks 1-10.
2. `mix compile --force --warnings-as-errors` — clean across the whole umbrella.
3. `mix format --check-formatted` scoped to every file touched across Tasks 1-10 (list them
   explicitly in the task's commit message or a scratch note; do not run repo-wide — the two
   pre-existing failures in `chain_monitor.ex`/`nav_init.ex` are not this spec's concern).
4. `mix credo --strict` — confirm no *new* findings in any file touched by Tasks 1-10 (compare
   against a `credo --strict` run on `master` for the same files if unsure whether a finding is
   pre-existing).
5. Security greps (must return zero hits, or only expected/reviewed hits):
   - `grep -rn "String.to_atom\|String.to_existing_atom" apps/data_collector/lib/data_collector/kraken* apps/data_collector/lib/data_collector/coinbase*` — must be empty (registry/symbol lookups must pattern-match or compare strings only, per the env rule).
   - `grep -rn "Logger\." apps/data_collector/lib/data_collector/kraken* apps/data_collector/lib/data_collector/coinbase*` — manually eyeball every hit; none may interpolate `credentials`, a raw `secret_key`/`api_key`/`passphrase`/PEM/JWT/WS-token value into the log message (account_id, order_id, symbol, and Kraken/Coinbase's own non-secret error/event payloads are fine).
   - Confirm `apps/data_collector/mix.exs`'s new `{:jose, "~> 1.11"}` line did not change `mix.lock` (`git diff mix.lock` empty — re-verify at the end of the whole spec, not just right after Task 5, in case anything downstream touched deps).
   - Confirm no test file in `apps/data_collector/test/kraken*`, `apps/data_collector/test/coinbase*` makes a real network call (grep for `HTTPoison`/`WebSockex`/literal `"https://api.kraken.com"`/`"https://api.coinbase.com"` inside test files — should only appear, if at all, as a string being asserted against inside a pure-function test, never dialed).

**`docs/superpowers/notes/kraken-coinbase-e2e-checklist.md`** — manual, human-run verification
script (not automated, no CI job runs it), one section per exchange plus a shared "what cannot be
verified" section, following `docs/superpowers/notes/okx-e2e-checklist.md`'s structure:

1. **Kraken section**: how to create a Kraken API key pair (Kraken account → API management →
   generate key, no separate "demo" mode exists — **this checklist necessarily uses real
   production Kraken credentials**, unlike OKX's demo-trading flow; call this out prominently at the
   top of the section, in bold, before any steps). `.env` vars to set
   (`KRAKEN_API_KEY`/`KRAKEN_SECRET_KEY`/`KRAKEN_BASE_URL`, matching Task 1's config). Steps: add a
   Kraken account in the UI (confirm no passphrase field renders); test the credential (confirm it
   calls `BalanceEx` successfully — note in the checklist that this is already a **live, real,
   authenticated** call, not a dry run, so use a key with read-only or minimal-trade-permission
   scoping for this step if the user's Kraken account setup allows it); **the AddOrder
   `validate=true` dry-run flow specifically**: place a strategy-triggered order against a real
   funded Kraken account with a strategy config the operator is confident will trigger a trade, but
   first manually confirm (outside the app, via a raw `curl`/Kraken UI test, or by temporarily
   wiring `validate: true` into a manual `KrakenClient.create_order/2` call from an `iex -S mix`
   session) whether Kraken's `validate=true` response includes a `txid` — the verified-notes doc
   flags this as genuinely unconfirmed from Kraken's own docs; record whichever answer is observed
   directly in this checklist file so future runs don't have to re-discover it. Verify a placed
   limit order appears in Kraken's own web UI open-orders view, then cancel it from the dashboard
   and confirm it disappears from Kraken's UI too (closing the same dashboard→adapter→real-exchange
   loop the OKX checklist verifies, just against Kraken's live host since no demo host exists).
2. **Coinbase section**: how to create CDP API keys (ECDSA/EC key type specifically — **not**
   Ed25519, per Task 5's target format) via the Coinbase Developer Platform portal, and how to
   download/copy the SEC1 PEM (`-----BEGIN EC PRIVATE KEY-----`) into the dashboard's Coinbase
   secret-key `<textarea>`. `.env` vars (`COINBASE_BASE_URL`, matching Task 5's config — the actual
   key name/PEM go through the UI, same "env vars are just a convenient place to hold values before
   pasting into the form" framing as the OKX checklist uses). **Sandbox smoke section**: hit
   `POST /api-sandbox.coinbase.com/api/v3/brokerage/orders` and `GET .../accounts` (no auth headers
   needed — confirm this really is auth-free as the verified notes state) and confirm the adapter's
   `Normalize` functions parse the fixed canned response into the expected internal shape without
   crashing; explicitly state this proves **wire-plumbing only**, not order-placement *behavior*,
   since the sandbox is proven (verified notes §5) to ignore request input entirely — do not
   interpret a successful sandbox smoke test as evidence that order placement logic is correct.
   **Live production section**: place a small real order against a funded production Coinbase
   account on a liquid USD- or USDC-quoted pair (per verified notes §3, **do not** use a
   USDT-quoted pair for this checklist unless the operator has independently confirmed their account
   can trade USDT — EU/EEA accounts almost certainly cannot, post-MiCA); verify the order appears in
   Coinbase's own web UI, confirm the dashboard's WS-driven fill/cancel state transitions match, and
   specifically eyeball whether the `"l"`/`"L"` (last-fill-qty/price) fields the adapter approximates
   (per Task 6/7's documented limitation) look reasonable against what Coinbase's own UI shows for
   the same fill, and record any discrepancy observed.
3. **Shared "what CANNOT be verified without live keys" section**: both adapters' entire private-
   endpoint surface (order placement/cancellation/open-orders/balances, and both WS private
   channels) requires real credentials and cannot be exercised by CI or by this spec's authors —
   this is a structural limitation of both exchanges (Kraken has no testnet at all; Coinbase's
   sandbox is real but proven behaviorally inert), not a gap in the implementation. State plainly
   that unit tests (Tasks 1-8) cover 100% of the pure normalization/mapping logic (the part that's
   actually likely to contain bugs — wrong field names, wrong status mapping, off-by-one delta
   math) via fixtures, and that this checklist covers the remaining, irreducible "does the wire
   protocol actually work against the real exchange" surface that no fixture can substitute for.

**Verify:** re-run `MIX_ENV=test mix test` one final time after writing the checklist doc (a
docs-only file shouldn't affect it, but confirm nothing was left uncommitted/broken from Tasks
1-10's cumulative changes).

---

## Review protocol (enforced by the workflow, not this doc)

Each task: implementer → reviewer (spec + quality, independent verification, runs tests itself) →
one fix round if FAIL → re-review. After all tasks: holistic review of the entire diff
(`git diff 791067f..HEAD`) → fixer applies any confirmed fixes → final full test run. Every
reviewer must verify claims by reading code and running commands, never by trusting reports.
