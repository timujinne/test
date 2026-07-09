# OKX Adapter — Manual E2E Checklist

This is a **manual, human-run** verification script. It requires real OKX demo-trading API
credentials and is **not automated** (no CI job runs this) — someone with an OKX account must
walk through it after any change that touches the OKX adapter, credential flow, or the
account/settings UI.

## 1. Create OKX demo API keys

1. Sign up / log into an OKX account at https://www.okx.com (no KYC needed just to generate demo
   keys, but you do need a registered account).
2. Switch to **Demo Trading**: click **Trade → Demo Trading** in the top nav (or go directly to
   the Demo Trading dashboard). This gives you a separate simulated balance from your real
   account.
3. Go to **Personal Center → Demo Trading → API** (sometimes surfaced as "Demo Trading API" under
   your profile/API management page while Demo Trading mode is active).
4. Create a new API key:
   - Set a **passphrase** (you choose this — remember it, it's required on every private call and
     is NOT recoverable, only resettable).
   - Permissions: enable **Trade** (needed to place/cancel orders) and **Read** (needed for
     balance/order queries). You do not need **Withdraw**.
   - IP whitelist: optional for demo keys; leave open if testing from a dev machine with a
     dynamic IP.
5. Save the three values OKX shows you **once**: API Key, Secret Key, Passphrase. These are demo
   keys — they don't expire and only work when requests carry `x-simulated-trading: 1`, which
   this app sets automatically whenever `OKX_DEMO=true` (the default).

## 2. Set environment variables

In your `.env` (copied from `.env.example`), set:

```bash
OKX_API_KEY=<your demo api key>
OKX_SECRET_KEY=<your demo secret key>
OKX_PASSPHRASE=<your demo passphrase>
OKX_DEMO=true
# OKX_BASE_URL defaults to https://www.okx.com — leave unset unless testing against a mock.
```

Note: these `OKX_*` env vars are **not** consumed directly by the app at request time — they're
just a convenient place to keep the values while you're doing this checklist. The credentials you
actually use to log into demo trading are entered **through the dashboard UI** in step 3 below
(they get Cloak-encrypted and stored in `api_credentials`), not read from the environment by the
trading engine. `OKX_DEMO` (env) does control the app-wide `config :data_collector, :okx, demo:`
flag (`config/dev.exs` / `config/runtime.exs`), which gates whether the app sends
`x-simulated-trading: 1` and which OKX host it talks to — leave it `true` for this whole checklist
so nothing touches real OKX funds.

Restart the Phoenix server after changing `.env` so `config/runtime.exs` re-reads it
(`make server` / `make server-iex`, or however your dev server is normally started — this repo's
dev server runs via `iex -S mix phx.server` per the team's dev-env notes).

## 3. Add the OKX account in the UI

1. Log into the dashboard, go to **Settings** (account/credentials page — `settings_live.ex`).
2. Click "Add account" (or equivalent) to open the account form.
3. In the **Exchange** dropdown, select **OKX** (should now be selectable, not "(coming soon)").
4. A **Passphrase** field should appear (only visible/required when Exchange = OKX — confirm the
   Binance flow does *not* show it).
5. Fill in: label (anything, e.g. "OKX Demo"), API Key, Secret Key, Passphrase (the three values
   from step 1), check "Testnet/Demo" if the form exposes that as a separate toggle (some builds
   fold this into the global `OKX_DEMO` config instead — check current form fields), submit.
6. Confirm the account now appears in the accounts list with exchange = OKX.
7. **Validation check**: try submitting the OKX form with the Passphrase field empty — it should
   be rejected with a validation error (passphrase is required for OKX, not for Binance).

## 4. Test the credential

1. On the new OKX account row, click **Test credential** (or equivalent action wired to
   `Credentials.test_credential/1`).
2. Expect success — this calls `GET /api/v5/account/balance` under the hood. If it fails, check:
   - API key/secret/passphrase typed correctly (passphrase is easy to fat-finger).
   - `OKX_DEMO=true` in `.env` and server restarted (a demo key against the live host, or a live
     key against demo mode, both fail auth).
   - Server logs (`Logger` output) for the OKX error `msg` — should NOT contain your secret key or
     passphrase in plaintext (spot-check this while you're here; it's a hard requirement of the
     adapter).

## 5. Start a Naive strategy on a liquid pair

1. Pick a liquid OKX spot pair available in demo trading, e.g. `BTCUSDT` (concat form as shown in
   this app's UI; OKX's own `instId` for it is `BTC-USDT`, translated internally by
   `DataCollector.OKX.Symbols`).
2. Create/select a strategy setting using the **Naive** strategy against the OKX account and that
   symbol, with a small quantity appropriate for demo balance (demo accounts start with a fake
   balance, typically enough BTC/USDT to place small test orders — check your demo balance first
   via the dashboard's balance view or OKX's own demo trading UI).
3. Activate/start the strategy from the dashboard.
4. Watch the dashboard order/position view for a placed order. You should see:
   - A ticker stream update flowing in for the symbol (confirms `OKXPublicStream` is connected and
     subscribed — check server logs for `OKXPublicStream: connected successfully` and a
     `subscriber added` line).
   - An order get placed once the strategy's entry condition triggers (confirms `OKXClient`
     `create_order/2` + normalization to Binance-shaped order maps works end-to-end).

## 6. Verify the order in OKX's own demo UI

1. Open OKX's web UI, switch to **Demo Trading**, go to **Orders → Order History** (or
   **Open Orders** if it hasn't filled yet).
2. Confirm an order appears there matching what the dashboard shows (same side, quantity, symbol).
   This closes the loop: dashboard → `OKXClient` → real OKX demo REST API → OKX's own UI.
3. If the order fills (market order or a limit order that crosses), confirm:
   - The dashboard shows the fill (status transitions e.g. `NEW` → `FILLED`), which exercises
     `OKXPrivateStream`'s `orders` channel subscription and the executionReport normalization
     (check server logs for `OKXPrivateStream (account ...): login ok, subscribing to orders` and
     no repeated reconnect/backoff warnings).

## 7. Stop the strategy and verify cancellation

1. Stop/deactivate the strategy from the dashboard while an order is still open (use a limit order
   away from market price if you want to guarantee it stays open long enough to cancel — a market
   order will likely fill instantly and there'll be nothing left to cancel).
2. Confirm the dashboard shows the order as cancelled.
3. Cross-check in OKX's own demo UI (**Orders → Order History**) that the order's status is
   `Canceled` there too (confirms `OKXClient.cancel_order/3` normalization and the OKX
   `POST /api/v5/trade/cancel-order` call worked).

## 8. Cleanup

- Deactivate/delete the test strategy setting if you don't want it restarting on next server boot
  (`StrategyManager` restores active strategies on startup).
- Demo API keys don't expire and cost nothing to leave configured, but consider removing the OKX
  account from `.env`/the dashboard if this was a one-off verification pass on a shared dev
  environment.

## Notes for whoever runs this

- Everything above talks to **OKX's real demo-trading infrastructure** over the network — it is
  not mocked. Expect normal network flakiness; retry rather than assuming a code regression on the
  first failure.
- If something fails, check `docs/superpowers/notes/okx-api-verified.md` for the exact API
  contracts this adapter was built against, and compare against OKX's current docs
  (https://www.okx.com/docs-v5/en/) in case OKX changed something since this plan was written.
- This checklist intentionally never touches OKX's **live** trading host — every step assumes
  `OKX_DEMO=true`. Do not run this against live keys without independently re-reviewing the whole
  adapter for safety first.
