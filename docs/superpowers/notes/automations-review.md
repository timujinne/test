# Trading Automations Review

Scope: `apps/trading_engine/lib/trading_engine/{trader,strategy_manager,order_manager,risk_manager,symbol_info,position_tracker,shared_position_tracker,stop_conditions_monitor,pending_strategies_manager}.ex`, `strategies/{naive,grid,dca,conditional_chain}.ex`, `apps/dashboard_web/lib/dashboard_web/live/chains_live.ex`.

Method: static code reading + cross-reference tracing (grep for callers) + one live `MIX_ENV=test mix test apps/trading_engine/test apps/dashboard_web/test` run to sanity-check current suite health. No app code was changed, no orders were placed, no live/authenticated exchange calls were made.

All line numbers below are current as of this branch (`worktree-kraken-coinbase`, based on `master@791067f`).

---

## Part A — Honest assessment per component

### `Trader` (trader.ex)

The core execution loop is solid: `init/1` builds subscriptions from `Strategy.requirements/1`, runs `check_for_recovery/4` to detect orphaned orders or in-flight chain state before doing anything, and `terminate/2` runs strategy `on_terminate/2` + (for Grid only) a bounded cancel-and-verify loop for open orders. `AccountSupervisor` gives `terminate/2` a generous 30s shutdown budget specifically so that cleanup can finish (account_supervisor.ex:18-20) — a thoughtful detail.

Two things materially undercut that resilience story:

- **`state.positions` is never updated after `init/1`** (trader.ex:149, and no other assignment to `positions:` anywhere in the file). It is initialized to `%{}` and stays `%{}` for the life of the process. `RiskManager.check_position_size/2` reads exactly this field. See Part B, #2.
- **Crash recovery is inconsistent with the rest of the app's bookkeeping.** `AccountSupervisor` starts Trader with `restart: :transient` (account_supervisor.ex:17), so an *abnormal* exit is auto-restarted by the `DynamicSupervisor` using the original `start_link` args — independently of `StrategyManager`, which has its own `Process.monitor`-based view of "is this running" and reacts to the same crash by deactivating the setting and forgetting about it. The result is a live trading process the rest of the app believes is stopped. See Part B, #1 — this is the most severe finding in this review.

Partial fills are handled correctly at the ownership layer (`owns_execution?/2` matches by order id, not account id, with a documented rationale for why account id isn't available in a raw `executionReport`) but downstream: PARTIALLY_FILLED just broadcasts a PubSub event and is otherwise a no-op for every current strategy except that `ConditionalChain` explicitly ignores it (see below).

The `:cancel_order` action, advertised as a valid `TradingEngine.Strategy.action()` return value in the behaviour's typespec, has no matching clause in `execute_action/2` (trader.ex:484-528, only `:noop` and both `{:place_order, _}` shapes are handled). No shipped strategy currently returns it, so this is latent, but a future strategy that does will crash the Trader with `FunctionClauseError` — which, given the point above, means an unmonitored zombie respawn.

### `StrategyManager` (strategy_manager.ex)

Good design for the common path: `handle_info({:strategy_activated, setting}, ...)` reloads the setting with fresh credentials, routes through `PendingStrategiesManager` if start conditions exist, and otherwise builds full `Trader` opts via `start_trader_for_setting/1` (lines 295-337), which is the *only* place in the codebase that correctly assembles `exchange`/`credentials`/`strategy`/`strategy_config`. `chains_live.ex` does not use this path — see Part B, #3.

`handle_info(:restore_active_strategies, ...)` (line 137) is scheduled 1000ms after `init/1` (line 88) and queries `Settings.list_active_settings()` from a process that is not a test process. This is fine in production but is a real, verifiable test-environment hazard — see Part B, #4.

The `{:DOWN, ...}` handler (lines 250-285) only *deactivates* the DB row on an unexpected crash; it never attempts to restart the strategy. Combined with `AccountSupervisor`'s `:transient` auto-restart, you get two independent and contradictory reactions to the same crash (see #1).

### `OrderManager` (order_manager.ex)

Confirmed dead code — `grep -rn "OrderManager\."` across the umbrella returns no call sites outside its own module and tests. Order persistence is instead done inline in `Trader.save_order_to_db/2` / `update_order_in_db/1` (trader.ex:209-231, 462-482), which is the actually-exercised path. Worth noting `OrderManager.dispatch_create_order/4` (order_manager.ex:17-43) passes raw Binance string values (`binance_order["price"]`, `binance_order["origQty"]`) straight into `Order.changeset/2` with no `Decimal.new/1` wrapping, whereas `Trader.save_order_to_db/2` explicitly wraps price/quantity/filled_qty in `Decimal.new/1` — i.e. the dead module's behavior has already drifted from the live one. See Part B, #9 for the recommendation.

### `RiskManager` (risk_manager.ex)

Three checks are wired: order-size cap, position-size cap, daily-loss cap (lines 21-28). In practice, only the first ever fires:

- `check_order_size/1` (lines 30-46) compares a single order's raw `quantity` against `Config.risk_limit(:max_order_size_btc)` (default `0.1`, config.ex:61). This genuinely runs on every order. But the limit is a single global constant literally named `_btc` and applied identically regardless of the symbol being traded (config.ex:59-61, no per-symbol/per-asset scaling, no USD-notional conversion). `0.1` is a sane cap for BTCUSDT and a nonsensical one for e.g. DOGEUSDT or SOLUSDT quantities.
- `check_position_size/2` (lines 48-59) can never reject anything: `calculate_position_size(state.positions)` always evaluates to `0` because `state.positions` is never populated (see Trader section, and #2 below). Since a single order is already capped below the position cap, this check is a permanent no-op today, not a "sometimes flaky" one.
- `check_daily_loss/1` (lines 64-75) queries `SharedData.Schemas.Trade` rows with a non-nil `pnl` for the account since UTC midnight. `SharedData.Trading.create_trade/1` — the only function that inserts a `Trade` row — has zero callers anywhere in the app (`grep -rn "Trading.create_trade\|create_trade(" apps` outside `trading.ex` itself returns nothing). The `trades` table is never populated by live trading, so this check also always evaluates to "0 loss" and can never fire.

Net assessment: **RiskManager's actual, functioning protection today is a single flat per-order quantity cap, applied with the same numeric threshold to every symbol.** The cumulative-position and daily-loss circuit breakers exist in code and read well, but are inert.

### `SymbolInfo` (symbol_info.ex)

ETS-cached, one GenServer call per (exchange, symbol) miss — reasonable design. On fetch failure (`{:error, reason}` from either `ExchangeRegistry.client_for/1` or `client.get_exchange_info/1`), it logs a warning and returns a hardcoded `{5, 2}` (price_precision, qty_precision) **without caching it** (symbol_info.ex:62-69 — the `else` branch has no `:ets.insert`). Not caching the failure means every subsequent lookup for that symbol re-attempts the fetch (self-healing, good), but it also means a transient failure silently degrades every order placed in that window to guessed precision, with no visible signal beyond a log line at `:warning` (which is filtered out of most day-to-day log views).

Blast radius: for LIMIT orders (Grid, ConditionalChain), a wrong price precision can trip `PRICE_FILTER` and get the order flat-out rejected (safe-ish failure) or — if the guessed precision happens to be *coarser* than the real tick size — could round to a price a step outside where the strategy intended, which is a silent correctness bug, not just a rejection. For quantity, `{price:5, qty:2}` is backwards relative to every real pair in this codebase's own reference table (see #6): every listed symbol has *more* decimals of quantity precision than price, and the fallback has it the other way around. This exact same fallback shape (`{5, 2}`) is independently duplicated (not delegated to `SymbolInfo`) in `naive.ex:185`, `grid.ex:263`, `dca.ex:291`.

Only `ConditionalChain` (conditional_chain.ex:770) actually calls `TradingEngine.SymbolInfo.get_precision/2`. See #6, #7.

### `PositionTracker` (position_tracker.ex)

Pure functions (`update_positions/2`, `calculate_pnl/2`, `average_entry_price/1`), correctly written, FIFO-lot semantics for reducing positions on SELL. Confirmed **zero callers anywhere in the app** (`grep -rn "TradingEngine.PositionTracker\b"` only matches its own `defmodule` line). Its list-of-lots shape (`[%{entry_price:, quantity:, timestamp:}]`, no `symbol` key) is also incompatible with the `%{symbol => %{quantity: Decimal}}` shape `RiskManager.calculate_position_size/1` expects, so even if someone wired it in naively it wouldn't directly plug the gap in #2 — the position-tracking subsystem was never finished end-to-end.

### `SharedPositionTracker` (shared_position_tracker.ex)

Also effectively dead in production: its public write API `record_fill/2` has zero callers, and `AccountCoordinator` (the only module that reads from it) itself has zero external callers (see below). Its automatic ingestion path, `handle_info({:execution_report, report}, state)` (lines 163-190), reads `report["account_id"] || "unknown"` (line 166) — but no `executionReport` ever carries an `account_id` key. Confirmed by checking every producer: `binance_websocket.ex:123` broadcasts the raw Binance payload verbatim, and `okx/normalize.ex:206-231`'s `execution_report/2` builds exactly the documented Binance-shape keys (`i, s, S, X, x, l, L, z, q`) and nothing else — `Trader.owns_execution?/2` (trader.ex:439-444) even has a code comment explicitly noting "Binance executionReport carries NO account identifier." So today, if this ingestion path is ever triggered, **every fill from every account is bucketed under the literal string `"unknown"`**, silently merging all accounts' positions. Currently harmless only because nothing reads the aggregated state; would corrupt data immediately if either `AccountCoordinator` or `SharedPositionTracker` is ever wired into the dashboard as their moduledocs suggest is the intent.

### `StopConditionsMonitor` (stop_conditions_monitor.ex)

`PriceCondition`-based start conditions (handled by `PendingStrategiesManager`, not this module) work fine — they evaluate raw ticker price against a threshold with no dependency on position state. But this module's *stop* conditions are a different story:

- `add_running_trader/3` in `strategy_manager.ex:352-356` always registers monitoring with `entry_state = %{entry_price: nil, position_size: Decimal.new(0), started_at: ...}`.
- `StopConditionsMonitor.update_pnl/2` (public API at stop_conditions_monitor.ex:43, backing `handle_cast({:update_pnl, ...})` at lines 127-149) is the *only* code path that ever updates `position_size`/`entry_price`/`pnl` on a monitored entry, and it has **zero callers anywhere in the app**.
- `calculate_pnl/2` (lines 288-301) short-circuits to `{0, 0}` whenever `position_size` compares equal to `0` — which, since it's never updated, is always.
- `TakeProfitCondition.evaluate/2` and `StopLossCondition.evaluate/2` (conditions/take_profit_condition.ex:32-50, conditions/stop_loss_condition.ex:33-52) both key off `market_data["pnl"]`/`["pnl_percent"]`, which are always `0` from the above.
- `MaxDailyLossCondition.evaluate/2` (conditions/max_daily_loss_condition.ex:30-53) keys off `market_data["daily_pnl"]`, sourced from `state.daily_pnl_by_account` (stop_conditions_monitor.ex:303-307) — also only ever written inside the dead `update_pnl` handler, so also permanently `0`.

**Net effect: take-profit, stop-loss, and max-daily-loss auto-stop conditions never fire in this codebase as it stands today.** A user who configures "stop loss at -5%" believes they have downside protection on their running strategy and have none — the condition is silently always-false. Only `PriceCondition`-as-a-*stop*-condition and `TimeStopCondition` (which don't depend on pnl) would actually work if configured as stop conditions.

### `PendingStrategiesManager` (pending_strategies_manager.ex)

Straightforward and correctly scoped: subscribes to `market:#{symbol}` lazily per pending strategy, evaluates `ConditionEvaluator` on each tick, broadcasts `{:conditions_met, setting}` which `StrategyManager` picks up to actually start the trader. No issues found here.

### Strategies

- **`Naive`** (naive.ex): simple and internally consistent. Keeps its own `position` in strategy state (not the `Trader`-level `positions` map RiskManager reads — another data-shape split worth being aware of). Uses a locally hardcoded `get_symbol_precision/1` (lines 172-186), not `SymbolInfo` — see #6.
- **`Grid`** (grid.ex): has explicit `# TODO: Fetch from Binance exchangeInfo API` (line 249) next to its own hardcoded precision table (lines 250-264) — the team already flagged this debt. Grid is also the only strategy `Trader.terminate/2` gives special open-order cleanup to (trader.ex:356-358); `ConditionalChain`'s resting LIMIT orders get no equivalent cleanup on stop.
- **`DCA`** (dca.ex): timer-driven, and its price source (`get_current_price/1`, lines 220-228) calls `DataCollector.BinanceClient.get_ticker_price/1` directly — not through `DataCollector.ExchangeRegistry`/`ExchangeClient`, and `state` doesn't even carry `exchange` (init at lines 94-106 has no `exchange:` field, despite `Trader.init/1` injecting `config["exchange"]` into every strategy's config at trader.ex:59). On a Kraken/OKX/Coinbase account this either fails every buy tick (symbol not recognized by Binance → logs `:error`, `{:noop, state}`, DCA silently never buys) or, for a symbol that happens to share a ticker with a Binance pair, sizes the order off Binance's price while executing on a different exchange's order book — see #5. Also has its own hardcoded precision table (lines 284-292), same shape/bug as Naive/Grid.
- **`ConditionalChain`** (conditional_chain.ex): the most carefully built of the four — persists state after every transition (`persist_state/1`), recovers cleanly via `Trader`'s `check_for_recovery/4` (goes to `:error` rather than risking a duplicate order if a pending order can't be confirmed, lines 183-190), and is the only strategy that consults the real `SymbolInfo` (line 770) and threads `exchange` through its own state (lines 145, 225, 258). It explicitly ignores `PARTIALLY_FILLED` (lines 343-345, logged at `:debug` and dropped) with no timeout — a step order that partially fills and then stalls parks the chain in `:awaiting_step`/`:awaiting_branch` indefinitely while the Trader is alive (recovery only kicks in on a restart). `init_from_recovery/2` (line 138) calls `String.to_existing_atom(state_string)` on a DB-persisted string; low risk in practice since the string always originates from this same module's own fixed atom set via `to_string/1`, but it's the one place in the reviewed files that brushes up against the project's "never `to_existing_atom` on external-ish input" rule and deserves a defensive pattern-match instead.

### `chains_live.ex`

`build_chain_config/1` and the step-builder helpers are fine. The lifecycle glue (`start_chain_execution/1`, `stop_chain_execution/1`, `cancel_chain_execution/1`, lines 854-911) bypasses `StrategyManager` entirely and talks to `AccountSupervisor` directly — and the start path is broken. See #3.

---

## Part B — Ranked improvement list

Each item: evidence, effort (S = same-day/1 file, M = multi-file/design-touching, L = cross-cutting), risk if left unfixed.

### 1. "Ghost trader": crashed strategies auto-restart invisibly and become unstoppable from the UI — **CRITICAL**

- **Evidence**: `AccountSupervisor.start_trader/2` starts the child with `restart: :transient` (account_supervisor.ex:17). Per `DynamicSupervisor` semantics, `:transient` children are automatically restarted (with the *original* `start_link` args, captured in the child_spec closure) whenever they exit abnormally — this restart is entirely internal to the supervisor and independent of `StrategyManager`. Meanwhile `StrategyManager.add_running_trader/3` tracks liveness via its own `Process.monitor/1` (strategy_manager.ex:348) and, on the resulting `{:DOWN, ...}` for an unexpected reason, removes the setting from its own `running_traders` map and calls `Settings.deactivate_setting/1` (lines 250-285) — it never calls `AccountSupervisor.stop_trader/1`. `strategies_live.ex`'s stop/deactivate action (lines 191-196) only broadcasts `{:strategy_deactivated, setting}`, which routes to `StrategyManager.stop_trader_for_setting/2` (strategy_manager.ex:383-411) — and that function is a no-op whenever `setting_id` isn't a key in `state.running_traders` (lines 387-390), which it no longer is after the crash. Net result: the DynamicSupervisor has already respawned a live Trader (fresh strategy state, real credentials, will place real orders) under the same `setting_id`, `StrategyManager` and the DB (`is_active`) both say it's stopped, and the only UI-driven stop path for non-chain strategies goes through `StrategyManager` and therefore does nothing.
- **Confidence**: verified by full code trace of `:transient` semantics + both bookkeeping paths; not empirically reproduced (would require deliberately crashing a live Trader against a running dev server, out of scope/unsafe for this review).
- **Effort**: S (1 file: `account_supervisor.ex`, change `restart: :transient` to `restart: :temporary`).
- **Risk of the fix**: loses automatic OTP-level restart-on-crash. This is an acceptable, arguably *safer* tradeoff: `Trader.init/1` already has a robust restart-time reconciliation path (`check_for_recovery/4`), so restarting is only ever safe to do through `StrategyManager`'s explicit `start_strategy/1`, which is exactly what this fix forces. If automatic recovery-after-crash is wanted, it should be `StrategyManager` explicitly re-issuing `start_strategy/1` after logging/alerting, not a bare supervisor restart that the rest of the app can't see.
- **Risk if unfixed**: unbounded — a live, unmonitored, unstoppable trading process is close to worst-case for a system that places real orders.

### 2. RiskManager's position-size and daily-loss checks are permanently inert — **CRITICAL**

- **Evidence**: `Trader` state field `positions: %{}` (trader.ex:149) is never reassigned anywhere else in the module (confirmed via `grep -n "positions" trader.ex`). `RiskManager.check_position_size/2` (risk_manager.ex:48-59) reads exactly this field via `calculate_position_size/1` (lines 123-128), so it always computes `0` and can never reject an order for exceeding `max_position_size`. Separately, `RiskManager.check_daily_loss/1` (lines 64-75) sources from `SharedData.Schemas.Trade` rows with non-nil `pnl`; `SharedData.Trading.create_trade/1` (the only insert path) has zero callers anywhere (`grep -rn "Trading.create_trade\|create_trade(" apps` outside `trading.ex` is empty), so the query always returns `0` and this check can never fire either.
- **Effort**: S/M. The position-size half is self-contained and small: track net filled quantity per symbol on `Trader`, updated in `handle_info({:execution_report, execution}, state)` (trader.ex:250-314) using the side/qty already extracted there, and feed that map (already the shape `RiskManager.calculate_position_size/1` expects) into `state.positions`. 1 file (`trader.ex`), no signature changes needed elsewhere. The daily-loss half is materially bigger (needs a real trade/PnL recording pipeline — nothing today ever computes realized PnL per fill) and is scoped to Future Work below.
- **Risk if unfixed**: the position-size cap — the only thing standing between a strategy re-buying into an already-large position and no cap at all — silently does nothing.

### 3. `chains_live.ex` "Start Chain" is broken; chain start/stop bypasses `StrategyManager` bookkeeping — **HIGH**

- **Evidence**: `start_chain_execution/1` (chains_live.ex:854-873) flips `is_active: true` in the DB and then calls `TradingEngine.AccountSupervisor.start_trader(updated_setting.account_id, setting_id: updated_setting.id)` — **only** `setting_id:` in `opts`. `AccountSupervisor.start_trader/2` (account_supervisor.ex:11-24) just adds `account_id` and forwards the rest verbatim to `Trader.start_link/1` → `Trader.init/1`, which does `Keyword.fetch!(opts, :exchange)`, `:credentials`, `:strategy`, `:strategy_config` (trader.ex:39-44) — all four are missing, so `Trader.init/1` raises `KeyError`, the GenServer never starts, and `DynamicSupervisor.start_child/2` returns an error tuple synchronously. The `handle_event("start_chain", ...)` caller (chains_live.ex:248-261) does surface this as a flash message rather than crashing the LiveView, but the DB row is left with `is_active: true` and no trader actually running — a second, silent state-desync bug layered on top of the crash. The only working way to start a strategy with correct opts is `StrategyManager.start_trader_for_setting/1` (strategy_manager.ex:295-337, private) / its public wrapper `StrategyManager.start_strategy/1` (lines 55-58).
- **Compounding note**: `stop_chain_execution/1` and `cancel_chain_execution/1` (chains_live.ex:875-911) call `AccountSupervisor.stop_trader/1` directly too — this actually *works* (Registry lookup by `setting_id` finds whatever's really running), but it means chain-started traders are never registered in `StrategyManager.running_traders`, so `StrategyManager.get_running_strategies/0`/`is_running?/1` are wrong for chains, and `StopConditionsMonitor` registration (which only happens inside `StrategyManager.add_running_trader/3`, strategy_manager.ex:347-360) never happens for a chain even if this bug is fixed by only patching the opts.
- **Effort**: S (1 file: `chains_live.ex`). Replace the three call sites with `TradingEngine.StrategyManager.start_strategy/1` and `TradingEngine.StrategyManager.stop_strategy/1`, which already build full opts, register the monitor, and wire stop-condition monitoring — same fix shape the known-issue prompt suggested.
- **Risk if unfixed**: the chains feature's primary "start" action is non-functional today.

### 4. `Trader.terminate/2` unsubscribes from ticker streams via a Binance-only call, ignoring `state.exchange` — **HIGH**, directly relevant to this branch

- **Evidence**: subscribing (trader.ex:84) correctly goes through the exchange-aware facade: `DataCollector.MarketStream.subscribe(exchange, sym)`. Unsubscribing on terminate (trader.ex:360-363) instead hardcodes `DataCollector.TickerStream.unsubscribe(sym)` — the Binance-specific stream, regardless of `state.exchange`. For any OKX (and, once added, Kraken/Coinbase) trader, this asymmetry means the real subscription (`OKXPublicStream`, etc.) is never told to decrement its subscriber count when the Trader stops; the reference count for that symbol never reaches zero and the public stream subscription is never cleaned up.
- **Effort**: S (1 file: `trader.ex`). Replace with `DataCollector.MarketStream.unsubscribe(state.exchange, sym)` — `MarketStream.unsubscribe/2` already exists with exactly this signature (market_stream.ex:26-31) and is simply never called.
- **Risk if unfixed**: growing leak of dangling public-stream subscriptions per non-Binance strategy stop/restart cycle; on the exchanges with connection/subscription limits this eventually causes new subscriptions to fail or wastes bandwidth on unwanted ticks forever.

### 5. `DCA` hardcodes `DataCollector.BinanceClient` for its price source — breaks on any non-Binance account — **HIGH**, directly relevant to this branch

- **Evidence**: `dca.ex:17` `alias DataCollector.BinanceClient`; `get_current_price/1` (lines 220-228) calls `BinanceClient.get_ticker_price/1` directly, never through `ExchangeRegistry`. `DCA`'s `state` (init, lines 94-106) has no `exchange` field at all, even though `Trader.init/1` injects `config["exchange"]` into every strategy's config (trader.ex:59) — DCA simply never reads it. On a Kraken/OKX/Coinbase account, every timer tick either fails outright (Binance doesn't recognize the symbol → `{:error, reason}` at line 157-159, logged, DCA silently never buys — a strategy that looks "active" and does nothing) or, for a ticker that happens to also exist on Binance, sizes the buy from Binance's price while actually executing on a different venue's book.
- **Effort**: S/M (1 file: `dca.ex`). Minimal fix: DCA already conditionally subscribes to ticks only when price-based stop conditions exist (`requirements/1`, lines 20-40); change it to always request `ticks: true`, cache the latest price from `on_tick/2` into `state.last_price` (already a field, currently only used for logging), and use that cached price in `on_timer/2` instead of calling `BinanceClient` — removing the hardcoded exchange dependency entirely and reusing the subscription `Trader` already sets up exchange-agnostically via `MarketStream.subscribe/2`.
- **Risk if unfixed**: DCA is silently non-functional (or mis-priced) on every non-Binance account — directly undermines the point of this branch.

### 6. Three strategies duplicate a hardcoded, Binance-only precision table instead of using `SymbolInfo` — **MEDIUM/HIGH**

- **Evidence**: `naive.ex:172-186`, `grid.ex:250-264` (with its own `# TODO: Fetch from Binance exchangeInfo API` at line 249), and `dca.ex:284-292` all define an identical local `get_symbol_precision/1` with the same five hardcoded symbols and the same `_ -> {5, 2}` fallback. Only `ConditionalChain` (conditional_chain.ex:769-771) calls the real, exchange-aware `TradingEngine.SymbolInfo.get_precision/2`. The fallback `{5, 2}` (price_precision=5, qty_precision=2) is backwards relative to every listed real pair in the same table (all have *more* qty decimals than price decimals) — for any symbol not in the table (which, on Kraken/Coinbase, is every symbol, since the table is Binance-ticker-shaped), quantity gets rounded to only 2 decimals, which is highly likely to violate the real `LOT_SIZE`/`stepSize` for anything but the highest-priced assets, causing rejected orders. `Grid` additionally rounds its LIMIT `price` with the same wrong-default precision, risking `PRICE_FILTER` rejection too.
- **Effort**: M (3 files, same mechanical change in each: thread `exchange` into strategy state at `init/1` — already available via `config["exchange"]`, trader.ex:59 — and replace the local `get_symbol_precision/1` with `TradingEngine.SymbolInfo.get_precision(state.exchange, state.symbol)`).
- **Risk if unfixed**: Naive/Grid/DCA give incorrect precision for any symbol outside their hardcoded five, which is every Kraken/Coinbase symbol by construction — orders rejected or, worse, accepted with wrong sizing.

### 7. `SymbolInfo` silently falls back to `{5, 2}` on any fetch failure, with no operator-visible signal — **MEDIUM**

- **Evidence**: `symbol_info.ex:55-69`. Failure path logs at `:warning` (easy to miss in day-to-day logs) and returns a guessed precision that is used to round both price and quantity for every order on that symbol until a later call happens to succeed. Not cached (no `:ets.insert` in the `else` branch, symbol_info.ex:62-69) — self-heals on the next lookup, but doesn't protect the order(s) placed during the failure window.
- **Effort**: S for the narrow fix (return `{:error, reason}` instead of a guessed tuple and let the one caller, `ConditionalChain.build_order_params/2`, treat that as a hard stop rather than silently trading with wrong precision); wiring an operator-facing alert on repeated failures is bigger (Future Work).
- **Risk if unfixed**: silent mis-sized/rejected orders during any transient exchange-info fetch failure, with only a `:warning`-level log as a trace.

### 8. Stop-loss / take-profit / max-daily-loss stop conditions never fire — **MEDIUM/HIGH** (feature works only by coincidence of naming)

- **Evidence**: see Part A, `StopConditionsMonitor` section — `entry_state.position_size` is hardcoded to `Decimal.new(0)` at registration (strategy_manager.ex:352-356) and only `StopConditionsMonitor.update_pnl/2` (never called by anything, confirmed via grep) can change it. `calculate_pnl/2` (stop_conditions_monitor.ex:288-301) therefore always returns `{0, 0}`, and `daily_pnl` is likewise always `0`. This makes `TakeProfitCondition`, `StopLossCondition`, and `MaxDailyLossCondition` permanently non-triggering.
- **Effort**: L — real fix needs a genuine live-PnL source, which depends on fixing #2 first (position tracking) plus piping fills into `StopConditionsMonitor.update_pnl/2` from somewhere (currently nothing does). Scoped to Future Work; the actionable near-term mitigation is a UI-level disclaimer/warning on stop-loss/take-profit condition configuration until this is wired.
- **Risk if unfixed**: users configuring stop-loss/take-profit believe they have automated downside protection and have none — the single highest user-trust risk in this review, but sized too large for a 1-3 file fix this round.

### 9. `OrderManager` is dead code with a subtly different (and arguably more buggy) persistence path than the live one — **LOW/MEDIUM**

- **Evidence**: `grep -rn "OrderManager\."` outside `order_manager.ex` and its own tests returns nothing. `dispatch_create_order/4` (order_manager.ex:17-43) inserts `price`/`quantity`/`filled_qty` from raw Binance string values with no `Decimal.new/1` wrapping, unlike `Trader.save_order_to_db/2` (trader.ex:209-231) which explicitly wraps them.
- **Recommendation**: delete rather than wire in. `Trader`'s inline persistence is the actually-exercised, currently-correct path; consolidating onto the dead module would mean adopting its stale field-typing behavior for no functional gain, and is a larger, riskier change than removing ~85 unused lines.
- **Effort**: S (delete `order_manager.ex` + verify no test/doc references).

### 10. `SharedPositionTracker` mis-attributes every fill to account `"unknown"`; `AccountCoordinator` is unused — **LOW today, latent data-corruption bug**

- **Evidence**: see Part A. `shared_position_tracker.ex:166` reads `report["account_id"]`, a key no `executionReport` producer (Binance WS, OKX private stream) ever sets — confirmed against `binance_websocket.ex:123` and `okx/normalize.ex:206-231`. Currently inert because `AccountCoordinator`'s public API and `SharedPositionTracker.record_fill/2` both have zero external callers.
- **Recommendation**: fix the `"unknown"` bucketing now while it's cheap (route the account id in via `on_order_placed` state rather than relying on the raw execution report, or simply stop subscribing this GenServer to `order_updates` directly and only update it explicitly from `Trader`, which does know its own `account_id`), or delete both modules pending an actual design decision — leaving them half-wired as "documentation of intent" risks someone flipping a switch and instantly corrupting cross-account position data.
- **Effort**: S/M depending on which path is chosen (2 files: `shared_position_tracker.ex` + call site in `trader.ex`, or straight deletion of both modules).

### 11. `execute_action/2` has no clause for `{:cancel_order, _}` despite it being a documented `Strategy.action()` — **LOW**

- **Evidence**: `strategy.ex`'s `@type action` includes `{:cancel_order, String.t()}`; `trader.ex:484-528`'s `execute_action/2` only matches `:noop` and both `{:place_order, _}` shapes. No shipped strategy emits it today.
- **Effort**: S — add the clause, call `exchange_client!(state).cancel_order/3`.
- **Risk if unfixed**: latent trap for the next strategy author; combined with #1, a crash here becomes an invisible zombie respawn.

### 12. Minor hardening items — **LOW**

- `conditional_chain.ex:138` — `String.to_existing_atom(state_string)` on a DB-persisted `current_state`. Low risk in practice (the string always originates from this module's own fixed atom set via `to_string/1`), but worth an explicit pattern-match against the known state atoms instead, both for defense-in-depth and to match the project's blanket rule against `to_existing_atom` on anything not a compile-time literal.
- `conditional_chain.ex:343-345` — `PARTIALLY_FILLED` is fully ignored with no timeout; a stalled partial fill parks the chain indefinitely while the Trader is alive.
- `trader.ex:356` — only `Grid` gets automatic open-order cleanup on stop; `ConditionalChain` also places resting LIMIT orders and gets none.
- `risk_manager.ex:17-19` / `config.ex:59-61` — risk limits are compile-time module attributes with no `Application.get_env` override path, despite `risk_manager.ex`'s comment claiming "tuning the config actually takes effect" — in practice "tuning" means editing source and redeploying.

---

## Known issues — verification summary

1. **`chains_live.ex` broken `start_trader` call** — **CONFIRMED**, real crash (`KeyError` via `Keyword.fetch!`), plus a secondary DB-desync (`is_active: true` survives the failed start). Fix: route through `StrategyManager.start_strategy/1` (and `stop_strategy/1` for consistency). See #3.
2. **`StrategyManager`'s 1s-delayed DB restore races the Ecto sandbox in tests** — **CONFIRMED as a real mechanism**, not empirically reproduced in this pass (current `apps/dashboard_web/test` suite finishes in 0.08s, well under the 1000ms delay, so the race window never opens today; `apps/trading_engine/test` never sets Sandbox mode to `:manual` so it isn't exposed there either). The mechanism is sound: `dashboard_web`'s and `shared_data`'s `test_helper.exs` both call `Ecto.Adapters.SQL.Sandbox.mode(SharedData.Repo, :manual)`; `dashboard_web` depends on `trading_engine`, so `TradingEngine.StrategyManager` boots in that VM too, and `Process.send_after(self(), :restore_active_strategies, 1000)` (strategy_manager.ex:88) will eventually fire from a non-test process with no checked-out sandbox connection once any test run in that VM takes longer than ~1s — raising `DBConnection.OwnershipError`, crashing the `StrategyManager` singleton, and (worse) potentially cascading into `TradingEngine.Supervisor`'s default restart-intensity limit (3 restarts / 5s, uncustomized in `application.ex`) if it crash-loops. There is an exact precedent for this class of fix already in `config/test.exs` ("Disable Oban queues, Cron and Pruner under test so background jobs do not run against the Sandbox-owned Repo (avoids ownership errors / flaky boots)"). Fix: gate the restore behind `Application.get_env(:trading_engine, :restore_on_boot, true)`, set to `false` in `config/test.exs`.
3. **`TradingEngine.OrderManager` has zero callers** — **CONFIRMED**. Recommend delete (see #9) rather than wire in — the live path (`Trader`) already does this correctly and has diverged from `OrderManager`'s stale, less-safe field typing.
4. **`SymbolInfo` silently falls back to `{5, 2}`** — **CONFIRMED**. See #7 for the fix and #6 for the compounding fact that three of four strategies don't even go through `SymbolInfo` in the first place.
5. **`RiskManager` — what it validates vs. what it should** — see the dedicated assessment above and #2: only the flat per-order quantity cap functions; position-size and daily-loss caps are dead code paths due to unpopulated backing state.

---

## TOP PICKS for this round

The 5 safest, highest-value fixes, each 1-2 files, no strategy-semantics changes — just plumbing/bookkeeping correctness:

1. **`account_supervisor.ex`: `restart: :transient` → `restart: :temporary`** (#1). Eliminates the invisible/unstoppable zombie-trader failure mode. 1 file, 1 line.
2. **`chains_live.ex`: route start/stop/cancel through `StrategyManager.start_strategy/1` / `stop_strategy/1`** (#3). Fixes an outright broken "Start Chain" button and brings chains into the same bookkeeping as every other strategy. 1 file.
3. **`trader.ex`: use `DataCollector.MarketStream.unsubscribe(state.exchange, sym)` on terminate** (#4). One-line fix for a real subscription leak that gets worse with every exchange this branch adds. 1 file.
4. **Gate `StrategyManager`'s `:restore_active_strategies` behind `Application.get_env(:trading_engine, :restore_on_boot, true)`, `false` in `config/test.exs`** (#2/known-issue-2). Matches an existing precedent in the same config file (Oban). Removes a real, if not-yet-triggered, source of test flakiness and singleton crash-looping. 2 files.
5. **`trader.ex`: populate `state.positions` from fills so `RiskManager.check_position_size/2` actually enforces the position cap** (#2). Restores the only currently-broken quantitative safety check that's self-contained enough to fix this round (daily-loss requires a real PnL pipeline — Future Work). 1 file.

Close runners-up that didn't make the cut only because of this round's item budget, not because they're less real: **#5 DCA's hardcoded `BinanceClient` price source** (directly breaks DCA on every non-Binance account) and **#6 the triplicated hardcoded precision table** (directly undermines multi-exchange correctness for Naive/Grid/DCA) — both are S/M, 1-3 files, and should be strong candidates for the very next round given this branch's purpose.

## Future work — explicitly out of scope this round

- A real trade/PnL recording pipeline (nothing currently calls `SharedData.Trading.create_trade/1`) feeding both `RiskManager.check_daily_loss/1` and `StopConditionsMonitor` — needed to make daily-loss caps and take-profit/stop-loss conditions actually work (#2 daily-loss half, #8).
- Canonical payload structs replacing raw Binance-shaped string-keyed maps threaded through `Trader`/strategies/`RiskManager`/`PositionTracker` — would also resolve the atom-key-vs-string-key and list-of-lots-vs-map-of-positions shape mismatches noted throughout this review, but is a cross-cutting rewrite, not a 1-3 file change.
- A real exchange-agnostic "current price" callback on `DataCollector.ExchangeClient` (today none exists; the tick-cache workaround proposed for DCA in #5 sidesteps needing one, but a proper callback would let DCA — and any future timer-only strategy — fetch price on demand rather than only from cached ticks).
- Deciding the fate of `AccountCoordinator`/`SharedPositionTracker`/`PositionTracker`: either finish wiring them into the dashboard with a consistent position-state shape and real account attribution, or remove them. Partially-built and silently wrong is the worst of both options (#10).
- Periodic reconciliation between `StrategyManager.running_traders` and what `AccountSupervisor`/`Registry` actually has alive, as defense-in-depth beyond the `:temporary` restart fix in #1.
- Per-symbol/per-asset risk limits (replacing the flat "`_btc`"-named constant applied to every symbol) and a runtime-tunable config source for `SharedData.Config.risk_limit/1` (today compile-time-only despite comments implying otherwise).
