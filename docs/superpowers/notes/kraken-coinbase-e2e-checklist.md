# Kraken + Coinbase Adapters — Manual E2E Checklist

This is a **manual, human-run** verification script. It requires real, live, funded API
credentials for both exchanges and is **not automated** (no CI job runs this, and none ever
should — see the "what cannot be verified" section below for why). Someone with a Kraken account
and a Coinbase account must walk through the relevant section after any change that touches
either adapter, the credential flow, or the account/settings UI.

Unlike `docs/superpowers/notes/okx-e2e-checklist.md`, **neither exchange has an OKX-style demo
trading environment**:
- Kraken has **no testnet or demo mode at all** — every step below (aside from the pure
  parsing/signature unit tests already covered by `mix test`) talks to Kraken's real,
  production, live-money API.
- Coinbase has a `api-sandbox.coinbase.com` host, but it is **not a real matching engine** — it
  needs no credentials and returns fixed, canned responses that ignore request input entirely
  (proven live, see `docs/superpowers/notes/coinbase-api-verified.md` §5). It is useful for
  exactly one thing: proving the adapter's HTTP/JSON wire-plumbing doesn't crash. It proves
  nothing about order-placement *behavior*.

Read this whole file before running anything against real funds. When in doubt, use the smallest
possible order size and a low-value/liquid pair.

---

## 1. Kraken section

**Kraken spot has no separate demo/testnet mode. Every step in this section — including "test the
credential" and "place an order" — talks to Kraken's real production API with real credentials
against real funds. There is no safe simulated alternative.** Use a fresh API key scoped to the
minimum permissions each step actually needs (see below), and keep order sizes tiny.

### 1.1 Create a Kraken API key pair

1. Log into your Kraken account at https://www.kraken.com, go to **Settings → API** (also
   reachable directly at https://www.kraken.com/u/security/api).
2. Click **Generate New Key**.
3. Permissions: for the "test the credential" step you only need **Query Funds** (read-only). For
   the order-placement step you additionally need **Create & Modify Orders** (and **Cancel/Close
   Orders** to close the loop). Do **not** grant **Withdraw Funds** — this adapter never needs it
   and there's no reason to expose that scope to a dev/test key.
4. Kraken shows the **API Key** and **Private Key** (base64-encoded secret) once — copy both
   immediately; the private key cannot be re-displayed, only regenerated.
5. There is no passphrase to set — Kraken's API has no third credential field (confirmed in
   `docs/superpowers/notes/kraken-api-verified.md` §1, and enforced by `KrakenClient`/`Kraken.Auth`
   never touching `credentials.passphrase`).

### 1.2 Set environment variables

In your `.env` (copied from `.env.example`):

```bash
KRAKEN_API_KEY=<your api key>
KRAKEN_SECRET_KEY=<your base64 private key>
# KRAKEN_BASE_URL defaults to https://api.kraken.com — leave unset, there is no alternate host.
```

As with the OKX checklist, these env vars are just a convenient staging place — the credentials
actually used by the trading engine are the ones entered **through the dashboard UI** (Cloak-
encrypted into `api_credentials`), not read directly from the environment at request time.
Restart the Phoenix server after editing `.env` so `config/runtime.exs` re-reads it.

### 1.3 Add the Kraken account in the UI

1. Log into the dashboard, go to **Settings**, click "Add account".
2. In the **Exchange** dropdown, select **Kraken** (should now be selectable, no "(coming soon)"
   suffix).
3. **Confirm no Passphrase field renders** for Kraken (only OKX shows one; Coinbase's two fields
   are relabeled but there's still no third passphrase field for either).
4. Fill in: label (e.g. "Kraken Live"), API Key, Secret Key (the two values from step 1.1),
   submit.
5. Confirm the account appears in the accounts list with exchange = Kraken.

### 1.4 Test the credential

1. On the new Kraken account row, click **Test credential**.
2. This is a **live, real, authenticated** call to `POST /0/private/BalanceEx` — not a dry run.
   Confirm it succeeds and returns your real account balances. If your key is Query-Funds-only
   (recommended for this step), this is the only private call it needs to make.
3. Spot-check server logs while you're here: no `Logger` line anywhere in
   `apps/data_collector/lib/data_collector/kraken*` should contain your API key, secret key, or
   the raw HMAC signature in plaintext (this was also grep-verified programmatically as part of
   Task 11's regression pass — see the repo's Task 11 commit for the exact commands run).

### 1.5 The `validate=true` dry-run flow — resolve the open question, record the answer here

Kraken's own docs are ambiguous about whether `AddOrder`'s `validate=true` dry-run flag still
returns a `txid` in the response (flagged explicitly as unconfirmed in
`docs/superpowers/notes/kraken-api-verified.md` §2/§6). Before placing any real order via a
strategy, resolve this manually and record the answer in this file for future runs:

1. From an `iex -S mix` session (or a raw `curl` against `https://api.kraken.com/0/private/AddOrder`
   with a hand-built signature, or Kraken's own API testing UI if it exposes one), call
   `DataCollector.KrakenClient.create_order/2` (or the equivalent raw request) with `validate: true`
   merged into the body, using a real Kraken account's credentials and a tiny, obviously
   never-fillable limit price (e.g. a BUY far below market) so nothing can accidentally execute
   even though it's `validate=true`.
2. Observe whether `result` contains a `txid` key.
3. **Record the observed answer here:**

   > `validate=true` on `AddOrder` — **NOT YET RUN**. Fill this in the first time someone executes
   > this checklist against a real Kraken account: does the JSON response include `result.txid`
   > when `validate: true` is set? (Yes/No, and the exact response shape observed.)

   This adapter's `KrakenClient.create_order/2` (Task 2) is intentionally written to build its
   Binance-shaped placement response directly from the known request + AddOrder ack rather than
   depend on this being present — so a "No" answer doesn't require any code change, only informs
   whether `validate=true` is usable as a smoke test at all going forward.

### 1.6 Place and observe a real limit order

1. Pick a liquid Kraken spot pair, e.g. `BTCUSD` (concat form as shown in this app's UI; Kraken's
   own altname for it is `XBTUSD`, translated internally by `DataCollector.Kraken.Symbols`).
2. Create/select a strategy setting (e.g. **Naive**) against the Kraken account and that symbol,
   with the smallest quantity Kraken's `ordermin` allows, and a limit price safely away from
   market (so it doesn't fill instantly and you have time to observe/cancel it).
3. Activate the strategy from the dashboard.
4. Confirm:
   - A ticker stream update flows in for the symbol (`KrakenPublicStream: connected successfully`
     and a `subscriber added` line in server logs).
   - The order gets placed once the strategy's entry condition triggers (`KrakenClient.create_order/2`
     + `Normalize.order_response_from_placement/2` producing a Binance-shaped order map).
5. Open Kraken's own web UI, go to **Trade → Orders** (or the account's Open Orders view), and
   confirm the same order appears there (same side, quantity, symbol, price). This closes the
   loop: dashboard → `KrakenClient` → real Kraken REST API → Kraken's own UI.
6. Confirm the dashboard's WS-driven state (via `KrakenPrivateStream`'s `executions` subscription)
   reflects the order as `NEW`/open — check server logs for
   `KrakenPrivateStream (account ...): got WS token, subscribing to executions` and no repeated
   reconnect/backoff warnings.

### 1.7 Cancel and verify

1. Cancel the order from the dashboard while it's still open.
2. Confirm the dashboard shows it as `CANCELED`.
3. Cross-check in Kraken's own web UI that the order disappears from the open-orders view (or
   shows as Canceled in order history) — confirms `KrakenClient.cancel_order/3` and the real
   `POST /0/private/CancelOrder` call worked end-to-end.

### 1.8 Cleanup

- Deactivate/delete the test strategy setting if you don't want it restarting on next server boot.
- Consider revoking or narrowing the Kraken API key's permissions after this pass, since it was
  necessarily tested against real funds.

---

## 2. Coinbase section

Coinbase's Advanced Trade API uses **CDP (Coinbase Developer Platform) API keys** with ES256 JWT
auth, not a classic API-key/secret pair. This adapter targets the **ECDSA / EC key type
specifically — not Ed25519** (per Task 5's target format; Ed25519 is CDP's default recommendation
today but this app's `Coinbase.Auth` only implements the EC/SEC1-PEM path).

### 2.1 Create a CDP EC API key

1. Log into the Coinbase Developer Platform portal at https://portal.cdp.coinbase.com/access/api
   (or **CDP Portal → API Keys** if navigating from the main CDP dashboard).
2. Create a new **Secret API Key** (the "trading"/Advanced Trade key type, not a Wallet API key).
3. When prompted for **key type**, choose **ECDSA** — the portal defaults to Ed25519, so this step
   is easy to miss; explicitly select ECDSA/EC.
4. Set permissions appropriate to the steps below: read-only (**View**) is enough for the
   credential-test step; you'll additionally need **Trade** for order placement.
5. Download or copy the two values CDP shows you:
   - The **key name**, shaped `organizations/{org_id}/apiKeys/{key_id}` — this is not secret by
     itself but shouldn't be logged either, out of general caution (matches Task 5's documented
     credentials-mapping decision).
   - The **EC private key PEM**, starting `-----BEGIN EC PRIVATE KEY-----` (SEC1 format). This
     value can only be downloaded once — save it somewhere safe immediately.

### 2.2 Set environment variables

In your `.env`:

```bash
COINBASE_API_KEY_NAME=organizations/your-org-id/apiKeys/your-key-id
COINBASE_EC_PRIVATE_KEY_PEM="-----BEGIN EC PRIVATE KEY-----\n...\n-----END EC PRIVATE KEY-----"
# COINBASE_BASE_URL defaults to https://api.coinbase.com — leave unset for the live section below.
```

Same framing as the OKX/Kraken checklists: these env vars are a convenient staging place. The
values you actually exercise end-to-end go **through the dashboard UI** — paste the key name into
the "Key Name" field and the full multi-line PEM into the "EC Private Key" `<textarea>` (Task 8's
UI change; confirm the textarea, not a single-line `<input>`, is what renders when Exchange =
Coinbase).

### 2.3 Sandbox smoke test (wire-plumbing only — read this before running it)

**This step proves the adapter's HTTP/JSON plumbing doesn't crash. It proves nothing about
order-placement correctness.** Coinbase's sandbox (`api-sandbox.coinbase.com`) is live-verified
(`docs/superpowers/notes/coinbase-api-verified.md` §5) to return a **fixed, canned response that
ignores request input entirely** — sending `side: BUY` can come back `side: SELL`, a custom
`client_order_id` comes back as a hardcoded `"sandbox_success_order"`, and a `market_market_ioc`
order configuration comes back describing `limit_limit_gtc`. Do not interpret a passing sandbox
smoke test as evidence that order-placement *logic* (side handling, sizing, status derivation) is
correct — only that the adapter can build a well-formed request and parse a well-formed response
without raising.

1. Confirm the sandbox needs no auth headers at all (this is itself part of what's being smoke
   tested): `curl https://api-sandbox.coinbase.com/api/v3/brokerage/accounts` and
   `curl -X POST https://api-sandbox.coinbase.com/api/v3/brokerage/orders -d '{...}'` with no
   `Authorization` header should both return `200`.
2. Manually feed the canned JSON shapes those calls return into
   `DataCollector.Coinbase.Normalize.account_response/1` and `order_response/2` (e.g. from an
   `iex -S mix` session) and confirm they parse into the expected Binance-shaped maps without
   raising.
3. Record the result as "wire plumbing confirmed" — nothing more.

### 2.4 Live production section

**This is a real order against a real, funded Coinbase account.** Use a liquid, low-value pair
and the smallest size Coinbase's `base_min_size` allows.

1. **Pair selection — read `docs/superpowers/notes/coinbase-api-verified.md` §3 before picking a
   symbol.** Prefer a **USD- or USDC-quoted** pair (e.g. `BTCUSD`/`BTCUSDC`) for this checklist.
   Do **not** use a USDT-quoted pair (e.g. `BTCUSDT`) unless you have independently confirmed your
   specific Coinbase account can trade USDT — Coinbase delisted USDT for EEA users effective 31
   March 2025 following the EU's MiCA regulation (Tether never sought MiCA authorization), and the
   product catalog does **not** reflect this per-account/per-region restriction: `BTC-USDT` will
   still show as `status: "online"` even for an account that will reject the order. If you're in
   the EU/EEA, assume USDT is unavailable to you regardless of what the catalog says.
2. Add the Coinbase account in the dashboard UI (Settings → Add account → Exchange = Coinbase),
   confirm the key-name field and the EC-PEM textarea render with Coinbase-specific labels/
   placeholders (per Task 8), and confirm no passphrase field renders.
3. Test the credential (a real `GET /api/v3/brokerage/accounts` call) and confirm it returns your
   real balances.
4. Start a strategy (e.g. Naive) against the Coinbase account and the chosen pair, small size,
   limit price away from market so you have time to observe it before it fills.
5. Confirm the order appears in Coinbase's own web UI (**Advanced Trade → Orders**), matching side/
   size/symbol.
6. Watch the dashboard's WS-driven fill/cancel state transitions (via `CoinbasePrivateStream`'s
   `user` channel subscription — check server logs for
   `CoinbasePrivateStream (account ...): connected, subscribing` and no repeated reconnect
   warnings).
7. **Specifically eyeball the `"l"`/`"L"` (last-fill-qty/price) fields the adapter approximates.**
   Per Task 6/7's documented limitation: Coinbase's `user` WS channel has no true last-fill-price
   field, so `"L"` is populated from `order_item["avg_price"]` (the order's running average fill
   price, not the price of the specific last fill) — and `"l"` (last-fill-qty) is derived as a
   `cumulative_quantity` delta tracked in the adapter's own process state, which **resets to zero
   on every WS reconnect**, so the very first execution report after a reconnect for an
   already-partially-filled order will over-report `"l"` as the entire cumulative fill rather than
   the true incremental delta. Compare what the dashboard shows for `"l"`/`"L"` against what
   Coinbase's own UI shows for the same fill and **record any discrepancy observed here:**

   > `l`/`L` field accuracy — **NOT YET RUN**. Fill this in the first time someone executes this
   > checklist against a real Coinbase account with an order that fills in more than one
   > increment: did the dashboard's reported last-fill qty/price match Coinbase's own UI, or show
   > the expected approximation error described above?

8. Cancel the order (if still open) and confirm both the dashboard and Coinbase's own UI show it
   as canceled.

### 2.5 Cleanup

- Deactivate/delete the test strategy setting.
- Consider narrowing/revoking the CDP key's permissions after this pass.

---

## 3. Shared — what CANNOT be verified without live keys

Both adapters' entire private-endpoint surface — order placement, cancellation, open-orders
queries, balance queries, and both exchanges' private WebSocket channels (Kraken's `executions`,
Coinbase's `user`) — requires real credentials and cannot be exercised by CI or by anyone without
a funded account on the relevant exchange. This is a **structural limitation of both exchanges**,
not a gap in this implementation:

- **Kraken has no testnet or demo mode at all.** The only built-in dry-run mechanism
  (`validate=true` on `AddOrder`) still requires live, real, authenticated credentials and its
  exact response shape (specifically whether `txid` is present) is undocumented by Kraken itself
  — see §1.5 above for the plan to resolve and record this.
- **Coinbase's sandbox is real and needs no credentials, but is behaviorally inert** — it returns
  fixed canned responses regardless of input (live-proven, see §2.3 above and
  `docs/superpowers/notes/coinbase-api-verified.md` §5). It can prove wire-plumbing works; it
  cannot prove order-placement logic is correct, because its "behavior" of echoing back what you
  sent does not exist.

What **unit tests already do cover, with high confidence, via canned fixtures (Tasks 1–8, no
network calls)**: 100% of the pure normalization/mapping logic in both adapters — the part of the
code most likely to actually contain bugs (wrong field names, wrong status-vocabulary mapping,
off-by-one delta math, wrong sign/side handling, mis-derived `cl_ord_id`/`client_order_id`
handling, tick/lot-size filter shapes, HMAC/JWT signature correctness). Every `Normalize`,
`Auth`, `Symbols`/`Products` module in `apps/data_collector/lib/data_collector/kraken*` and
`coinbase*` has a corresponding fixture-based test file exercising exactly this surface.

What this checklist covers instead is the remaining, irreducible surface that **no fixture can
substitute for**: does the wire protocol actually work against the real exchange (correct auth
headers/signatures accepted, correct HTTP paths, correct WS subscribe frames, correct reconnect/
token-refresh behavior over a real network), and does a real order placed through the dashboard
actually show up — and later cancel/fill — in the exchange's own UI. That loop can only be closed
by a human, with real credentials, running the steps above.
