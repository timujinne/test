# OKX Adapter — Implementation Plan (compressed context + tasks)

**Date:** 2026-07-09 · **Branch:** `worktree-okx-adapter` (worktree at `/app/.claude/worktrees/exchange-picker-ui` — directory name is legacy, ignore it) · **Base:** local `master` @ `49caf27`

**Goal:** Make OKX the first fully working non-Binance exchange (EU/MiCA-licensed, has a real demo-trading environment). After this plan: a user can add an OKX account (API key + secret + passphrase, demo or live), see it in the UI, and run existing strategies (Naive/Grid/DCA) against OKX spot markets.

---

## 1. Compressed context — what already exists (verified in code)

Elixir/Phoenix umbrella: `shared_data` ← `data_collector` ← `trading_engine` ← `dashboard_web`. PubSub: `BinanceSystem.PubSub`.

**Multi-exchange foundation (merged to master):**
- `DataCollector.ExchangeClient` behaviour (`apps/data_collector/lib/data_collector/exchange_client.ex`) — 5 callbacks, signatures currently `(api_key, secret_key, ...)`: `get_account/2`, `create_order/3`, `cancel_order/4`, `get_open_orders/3`, `get_exchange_info/1`.
- `DataCollector.ExchangeRegistry.client_for/1` — string pattern match, `"binance"` → `BinanceClient`, anything else → `{:error, {:unsupported_exchange, s}}`. Never converts input to atoms (security invariant — keep it).
- `DataCollector.BinanceClient` — implements the behaviour; also has extra public functions used directly by dashboard_web (`get_balances/2`, `get_ticker_price/1`, `get_klines/3`, `get_depth/2`, `get_all_orders/4`, `get_my_trades/4`, `cancel_all_orders/3`, `get_all_ticker_prices/0`, `get_24h_ticker/1`, `get_exchange_info/0`).
- `api_credentials` table/schema: `api_key`/`secret_key` (Cloak-encrypted `SharedData.Encrypted.Binary`), `label`, `is_active`, `is_testnet`, `exchange` (string, default `"binance"`, `validate_inclusion` vs `@supported_exchanges ["binance"]` in `apps/shared_data/lib/shared_data/schemas/api_credential.ex`). **No passphrase field yet** — OKX needs one.
- `orders` uniqueness = `(account_id, order_id)` (composite index `orders_account_id_order_id_index`; changeset uses `error_key: :order_id`).
- `SharedData.Credentials.test_credential/1` dispatches via registry using `apply/3` (shared_data must NOT compile-time-depend on data_collector — umbrella compile order; keep the `apply/3` pattern for any data_collector call from shared_data).
- `TradingEngine.StrategyManager.start_trader_for_setting/1` (`strategy_manager.ex:319-329`) passes opts `[setting_id, account_id, exchange, api_key, secret_key, strategy, strategy_config]` to `AccountSupervisor.start_trader/2`.
- `TradingEngine.Trader` (`trader.ex`): `init/1` does `Keyword.fetch!` on those opts; state map has `exchange`, `api_key`, `secret_key`; dispatch helper `exchange_client!/1` (raises on unsupported); order call sites use `exchange_client!(state).create_order(state.api_key, state.secret_key, params)`; recovery helpers `check_for_recovery/5`, `check_orphaned_orders/4`, `verify_and_build_recovery/5` thread `(exchange, api_key, secret_key)` positionally.
- `TradingEngine.OrderManager` — dispatches via registry but has **zero callers** (dead code; leave as-is unless a task says otherwise).
- Exchange picker UI (merged): `apps/dashboard_web/forms/account_form.ex` — embedded schema with `exchange` field, `@supported_exchanges ["binance"]`, `validate_inclusion` in `changeset/2` (create), NOT cast in `changeset_for_edit/2` (immutable after create). `settings_live.ex` — `<select name="account[exchange]">` with binance enabled, kraken/okx/coinbase `disabled` "(coming soon)"; `create_account_with_credentials/3` puts `"exchange" => params["exchange"] || "binance"` into `credential_params` (~line 626).

**Known Binance coupling still in place (relevant to this plan):**
- Strategies/trackers read **raw Binance payload keys** directly: ticker `market_data["c"]` (last price), executionReport `["i"]` orderId, `["s"]` symbol, `["S"]` BUY/SELL, `["X"]` status, `["x"]` exec type, `["l"]` last fill qty, `["L"]` last fill price, `["z"]` cum fill qty, `["q"]` orig qty. Files: `strategies/naive.ex`, `grid.ex`, `dca.ex`, `conditional_chain.ex`, `position_tracker.ex`, `shared_position_tracker.ex`, `stop_conditions_monitor.ex`, `pending_strategies_manager.ex`, `trader.ex:243,423,447-449`, `order_manager.ex:59-67`.
- REST order responses consumed by keys: `"orderId"`, `"clientOrderId"`, `"symbol"`, `"type"`, `"side"`, `"price"`, `"origQty"`, `"executedQty"`, `"status"`, `"timeInForce"` (see `order_manager.ex:17-27`, `trader.ex:162`).
- `Trader` subscribes market data via `DataCollector.TickerStream.subscribe(sym)` + PubSub `"market:#{sym}"` (`trader.ex:80-84`); order updates via PubSub `"order_updates"` with `{:execution_report, map}` messages.
- `TradingEngine.SymbolInfo` — global ETS keyed by symbol only, fetches `DataCollector.BinanceClient.get_exchange_info(symbol)`, parses Binance filters `PRICE_FILTER/tickSize`, `LOT_SIZE/stepSize` → `{price_precision, qty_precision}`. Single caller: `conditional_chain.ex:767`.
- `dashboard_web` LiveViews call `BinanceClient` directly (~20 sites) — **out of scope here**, they keep working for Binance accounts; OKX accounts get engine-level support first.

**KEY ARCHITECTURAL DECISION (transitional, deliberate):** the OKX adapter **normalizes all its payloads INTO Binance-shaped maps** (both REST responses and WS events). This avoids refactoring ~10 strategy-layer modules now. The canonical-struct refactor stays a separate future plan. Every normalization must match the exact key contracts listed above.

**Environment gotchas (mandatory):**
- Container exports `MIX_ENV=dev`; **always** run tests as `MIX_ENV=test mix test ...` (plain `mix test` fails with a sandbox error).
- Dev Phoenix server runs from `/app` (tmux `Binance:1.2`) — never modify `/app`, work only in this worktree.
- `deps` in this worktree is a symlink to `/app/deps` (mix.lock identical) — do not commit it; `_build` is local.
- Repo-wide `mix format --check-formatted` fails on 2 pre-existing unrelated files (`chain_monitor.ex`, `nav_init.ex`) and `mix credo --strict` exits 30 on pre-existing findings — check formatting **scoped to files you touch**; do not "fix" pre-existing noise.
- Commit after each task; never push; never merge to master.

## 2. OKX API essentials (to be VERIFIED by Task 0 scout against https://www.okx.com/docs-v5/en/ — treat as strong prior, not gospel)

- REST base `https://www.okx.com`; demo mode = same host + header `x-simulated-trading: 1`. Demo API keys are created in OKX web UI (Trade → Demo Trading → Personal Center → Demo Trading API); they never expire and only work against demo.
- Auth headers on private calls: `OK-ACCESS-KEY`, `OK-ACCESS-SIGN`, `OK-ACCESS-TIMESTAMP` (ISO8601 UTC ms, e.g. `2020-12-08T09:08:57.715Z`), `OK-ACCESS-PASSPHRASE`. Signature = `Base64.encode64(:crypto.mac(:hmac, :sha256, secret, timestamp <> method <> request_path_with_query <> body))`.
- Response envelope: `%{"code" => "0", "msg" => "", "data" => [...]}`; non-"0" code = error.
- Endpoints (spot): `GET /api/v5/account/balance`; `POST /api/v5/trade/order` (JSON body: `instId`, `tdMode: "cash"`, `side: "buy"|"sell"`, `ordType: "market"|"limit"`, `sz`, `px` for limit); `POST /api/v5/trade/cancel-order` (`instId`, `ordId`); `GET /api/v5/trade/orders-pending?instType=SPOT[&instId=]`; `GET /api/v5/public/instruments?instType=SPOT`; `GET /api/v5/market/ticker?instId=`; `GET /api/v5/market/candles?instId=&bar=`.
- **Market-buy gotcha:** for spot market BUY orders `sz` defaults to QUOTE currency; pass `tgtCcy: "base_ccy"` so `sz` means base quantity (matching Binance `quantity` semantics). Scout must verify.
- Instrument fields: `instId` ("BTC-USDT"), `tickSz`, `lotSz`, `minSz`, `baseCcy`, `quoteCcy`.
- Order states: `live`→NEW, `partially_filled`→PARTIALLY_FILLED, `filled`→FILLED, `canceled`→CANCELED.
- WS: public `wss://ws.okx.com:8443/ws/v5/public`, private `wss://ws.okx.com:8443/ws/v5/private`; demo WS host `wspap.okx.com` (scout: verify exact demo URLs incl. any `brokerId` query). Private login op: sign over `timestamp + "GET" + "/users/self/verify"` (timestamp = unix seconds for WS). Channels: `tickers` (arg `instId`), `orders` (arg `instType: "SPOT"`). Keepalive: send `"ping"` if idle >~25s, expect `"pong"`.

## 3. Tasks

### Task 0 — Scout: verify OKX API facts (NO code changes)
Create `docs/superpowers/notes/okx-api-verified.md`. Use WebFetch/WebSearch on official OKX docs to verify/correct EVERY item in section 2. Must contain: exact REST base + demo header; signature recipe with one worked example (fake secret, computed expected Base64 — implementers turn this into a unit test); endpoint paths + required params for the 7 endpoints above; market-buy `sz`/`tgtCcy` semantics; WS URLs (live + demo, public + private); WS login recipe; JSON payload examples for `tickers` and `orders` channel events (copy real examples from docs); order state list; instrument fields. Flag any item where docs disagree with section 2. Commit the notes file.

### Task 1 — Passphrase column + schema
- Migration `add :passphrase, :binary, null: true` to `api_credentials` (nullable — Binance creds don't have one). Schema: `field :passphrase, SharedData.Encrypted.Binary` (Cloak-encrypted like api_key/secret_key), add `:passphrase` to cast list. No validate_required (only OKX needs it; requiredness is enforced in Task 6's form logic, and adapter errors clearly if missing).
- Run migration in dev AND test envs. TDD: extend `apps/shared_data/test/schemas/api_credential_test.exs` — passphrase accepted+persisted (encrypted, use Sandbox checkout + insert like `order_test.exs` does), absent passphrase fine.

### Task 2 — Credentials-map seam refactor
Change `ExchangeClient` behaviour callbacks to take a credentials map instead of separate keys:
```elixir
@type credentials :: %{api_key: String.t(), secret_key: String.t(), passphrase: String.t() | nil}
@callback get_account(credentials()) :: Types.result(map())
@callback create_order(credentials(), Types.order_params()) :: Types.result(Types.order())
@callback cancel_order(credentials(), Types.symbol(), Types.order_id()) :: Types.result(map())
@callback get_open_orders(credentials(), Types.symbol() | nil) :: Types.result([map()])
@callback get_exchange_info(Types.symbol()) :: Types.result(map())  # unchanged, public
```
- `BinanceClient`: add thin behaviour-impl heads that destructure the map and delegate to the EXISTING two-arg public functions (which stay untouched — dashboard_web calls them directly). E.g. `def get_account(%{api_key: k, secret_key: s}), do: get_account(k, s)`.
- `Trader`: state gets `credentials: %{api_key:, secret_key:, passphrase:}` (keep it as the ONLY credential storage — remove separate `api_key`/`secret_key` keys from state and update all their usage sites incl. the recovery helper chain: thread `(exchange, credentials)` instead of `(exchange, api_key, secret_key)`); `init/1` reads `credentials = Keyword.fetch!(opts, :credentials)`.
- `StrategyManager` opts: replace `api_key:`/`secret_key:` with `credentials: %{api_key: c.api_key, secret_key: c.secret_key, passphrase: c.passphrase}` (c = `account.api_credential`).
- `SharedData.Credentials.test_credential/1`: build the map from the credential struct, keep `apply/3`.
- `OrderManager`: same signature update (it has zero callers; keep internally consistent).
- All existing tests must stay green (89 currently); `mix compile --warnings-as-errors` clean.

### Task 3 — OKX config + symbol mapping
- Runtime config: in `config/runtime.exs` AND `config/dev.exs`/`test.exs` add `config :data_collector, :okx, base_url: System.get_env("OKX_BASE_URL", "https://www.okx.com"), demo: System.get_env("OKX_DEMO", "true") in ~w(true 1), ws_public_url: ..., ws_private_url: ...` (URLs per scout notes; demo defaults TRUE in dev, read at runtime — `Application.get_env`, NOT `compile_env`). Update `.env.example` (OKX_API_KEY/OKX_SECRET_KEY/OKX_PASSPHRASE placeholders + OKX_DEMO=true).
- `DataCollector.OKX.Symbols` module: fetches `GET /public/instruments?instType=SPOT` (public, unauthenticated), caches in ETS: concat("BTCUSDT") ↔ instId("BTC-USDT") both directions + per-symbol `%{tick_sz, lot_sz, min_sz}`. Public API: `to_inst_id/1`, `to_concat/1`, `instrument_info/1` (concat input), each `{:ok, _} | {:error, :unknown_symbol}`; lazy-load on first miss + refresh on unknown. GenServer + ETS following `SymbolInfo`'s pattern. Unit tests with fixture data (no live HTTP: test the pure mapping/parse functions on a canned instruments JSON fixture).

### Task 4 — `DataCollector.OKXClient` (REST, implements ExchangeClient)
New file `apps/data_collector/lib/data_collector/okx_client.ex` + `apps/data_collector/lib/data_collector/okx/auth.ex`.
- `OKX.Auth.sign(secret, timestamp, method, path_with_query, body)` → Base64 HMAC-SHA256; `headers(creds, method, path, body)` builds the 4 OK-ACCESS-* headers + `x-simulated-trading: 1` when demo config on. Unit test against the scout's worked example vector.
- Behaviour callbacks (credentials-map signatures from Task 2). Every call: HTTPoison, wrapped in `DataCollector.CircuitBreaker.call(:okx_api, fn -> ... end)`; parse envelope (`"code" != "0"` → `{:error, msg}`).
- **Normalization to Binance shapes** (exact contracts):
  - `create_order/2`: input `order_params` is Binance-format (`%{symbol: "BTCUSDT", side: "BUY", type: "MARKET"|"LIMIT", quantity: q, price: p, timeInForce: _}`). Map: symbol→instId via `OKX.Symbols`, side downcase, type MARKET→market/LIMIT→limit, quantity→sz (+ `tgtCcy: "base_ccy"` for market buys per scout), price→px. Response data[0] (`ordId`, `clOrdId`, `sCode`) → then GET the order (`/api/v5/trade/order?instId=&ordId=`) to build full Binance-shaped reply: `%{"orderId" => ordId, "clientOrderId" => clOrdId, "symbol" => concat, "type" => upcased, "side" => upcased, "price" => px, "origQty" => sz, "executedQty" => accFillSz, "status" => mapped_state, "timeInForce" => "GTC"}`.
  - `cancel_order/3`: symbol concat→instId, returns Binance-shaped `%{"orderId" => ..., "status" => "CANCELED", "symbol" => concat}`.
  - `get_open_orders/2`: orders-pending → list of Binance-shaped order maps (same keys as above).
  - `get_account/1`: `/account/balance` → Binance-shaped `%{"balances" => [%{"asset" => ccy, "free" => availBal, "locked" => frozenBal}], "accountType" => "SPOT"}`.
  - `get_exchange_info/1`: from `OKX.Symbols.instrument_info/1` build `%{"symbols" => [%{"symbol" => concat, "filters" => [%{"filterType" => "PRICE_FILTER", "tickSize" => tick_sz}, %{"filterType" => "LOT_SIZE", "stepSize" => lot_sz, "minQty" => min_sz}]}]}` (SymbolInfo-compatible).
- Order state mapping helper (shared with Task 5, put in `DataCollector.OKX.Normalize` module): live→"NEW", partially_filled→"PARTIALLY_FILLED", filled→"FILLED", canceled→"CANCELED"; unknown → log warning, pass through upcased.
- Unit tests: normalization functions on canned OKX response fixtures (pure functions — factor them so they're testable without HTTP), auth vector test.

### Task 5 — OKX WebSockets (public tickers + private orders)
New: `apps/data_collector/lib/data_collector/okx_public_stream.ex`, `okx_private_stream.ex`, `okx/normalize.ex` (if not created in Task 4).
- **First read `apps/data_collector/lib/data_collector/ticker_stream.ex` and `binance_websocket.ex`** to copy: the WebSockex patterns, reconnect/backoff conventions, subscriber-count API contract of `TickerStream.subscribe/1`, and the EXACT ticker map shape + PubSub message tuple that `MarketData`/strategies consume (`{:ticker, map}` on `"market:#{concat}"`, map must include at least `"s"` and `"c"`; replicate whatever else TickerStream includes).
- `OKXPublicStream`: single connection (started under DataCollector supervision, lazily), `subscribe(concat_symbol)` mirroring TickerStream's contract; subscribes OKX `tickers` channel by instId; converts each event to the Binance ticker shape (`"c"` = `last`, `"s"` = concat, etc. per Normalize) and broadcasts.
- `OKXPrivateStream`: one per account (DynamicSupervisor `DataCollector.OKXPrivateSupervisor` + Registry keyed by account_id; add both to data_collector's application supervision tree). `start_stream(account_id, credentials)` idempotent. On connect: login op (per scout recipe), subscribe `orders` channel (SPOT); each order event → Binance executionReport shape: `%{"e" => "executionReport", "i" => ordId, "s" => concat, "S" => upcased side, "X" => mapped state, "x" => "TRADE" when fill else "NEW"/"CANCELED", "l" => fillSz, "L" => fillPx, "z" => accFillSz, "q" => sz}` → broadcast `{:execution_report, msg}` to `"order_updates"`. Ping keepalive + exponential reconnect backoff copied from BinanceWebSocket conventions; re-login+resubscribe after reconnect.
- `DataCollector.MarketStream` facade: `subscribe(exchange, concat_symbol)` → `"binance"`→`TickerStream.subscribe/1`, `"okx"`→`OKXPublicStream.subscribe/1`, else error.
- `Trader` changes: `init/1` subscribes via `MarketStream.subscribe(exchange, sym)` (replacing direct TickerStream call, same handling of `{:ok, count}`); when `exchange == "okx"` and `requirements.executions`, call `DataCollector.OKXPrivateStream.ensure_started(account_id, credentials)` (via `apply/3`? no — trading_engine already depends on data_collector, direct call fine).
- Unit tests: Normalize event→executionReport/ticker conversions on canned OKX WS payload fixtures (from scout notes examples).

### Task 6 — Enable OKX end-to-end (registry, validation, UI, SymbolInfo)
- `ExchangeRegistry`: `client_for("okx") → {:ok, DataCollector.OKXClient}`. Update `exchange_registry_test.exs` (okx now ok; kraken still error).
- `ApiCredential` `@supported_exchanges ["binance", "okx"]`; same in `AccountForm`. Update `api_credential_test.exs` accordingly (kraken still rejected).
- `settings_live.ex`: OKX `<option>` becomes enabled (drop `disabled` + "(coming soon)" for okx only); add a Passphrase input field (type password, `name="account[passphrase]"`, shown/required only when selected exchange is "okx" — use the form's current exchange value to conditionally render; on validate event the form re-renders so conditional display works); `credential_params` gets `"passphrase" => params["passphrase"]`. `AccountForm`: add `field :passphrase, :string`, cast it in `changeset/2`, `validate_required([:passphrase])` ONLY when `get_field(changeset, :exchange) == "okx"`; NOT cast in `changeset_for_edit/2`... exception: editing an OKX account's keys should allow updating passphrase together with api/secret keys — cast passphrase in edit changeset too, but no requiredness (empty = keep current). `update_account_with_credentials` in settings_live: include passphrase in `credential_updates` only when non-empty.
- `SymbolInfo` exchange-aware: ETS key `{exchange, symbol}`, `get_precision(exchange, symbol)` (keep `get_precision/1` head defaulting to `"binance"` for compatibility), fetch via `ExchangeRegistry.client_for(exchange)` → `client.get_exchange_info(symbol)`. Trader `init/1`: `strategy_config = Map.put(strategy_config, "exchange", exchange)` so strategies know their exchange; `conditional_chain.ex:767` → `SymbolInfo.get_precision(config["exchange"] || "binance", symbol)` (check how config is accessible at that call site; thread minimally).
- Tests: form validation (okx requires passphrase, binance doesn't; kraken still rejected), registry, SymbolInfo key change compile-safe.

### Task 7 — Regression + E2E instructions
- `MIX_ENV=test mix test` — full suite green (89 + all new tests).
- `mix compile --force --warnings-as-errors` clean; `mix format --check-formatted` scoped to all files touched by Tasks 1-6.
- Grep sanity: no `String.to_atom` on external input anywhere new; no plaintext credential logging (check every new `Logger` call); `x-simulated-trading` header only attached when demo config true.
- Write `docs/superpowers/notes/okx-e2e-checklist.md`: how the user creates OKX demo keys, .env vars to set, and a step-by-step manual E2E script (add OKX account in UI → test credential → start Naive strategy on a liquid pair → verify order placed in OKX demo UI → stop strategy → verify cancellation). This E2E requires user-supplied demo keys and is NOT automated.

## 4. Review protocol (enforced by the workflow, not this doc)
Each task: Sonnet implementer → Sonnet reviewer (spec + quality, independent verification, runs tests itself) → one fix round if FAIL → re-review. After all tasks: Opus holistic review of the entire diff (`git diff 49caf27..HEAD`) → Opus fixer applies any confirmed fixes → final full test run. Every reviewer must verify claims by reading code and running commands, never by trusting reports.
