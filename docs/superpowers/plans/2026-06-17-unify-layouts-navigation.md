# Unify Layouts & Navigation Under PhoenixKit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three custom layouts and custom nav with PhoenixKit's native admin chrome — one unified header everywhere, trading pages inside the PhoenixKit admin sidebar (above PhoenixKit items), obsolete user-settings dashboard removed.

**Architecture:** Trading LiveViews are registered as `config :phoenix_kit, :admin_dashboard_tabs` entries with a `live_view:` key. PhoenixKit's `phoenix_kit_routes()` macro auto-generates their routes inside the shared `:phoenix_kit_admin` live_session, which already supplies authentication + the admin layout (header + sidebar). The LiveViews render plain content (no layout wrapper). Public/blog pages keep a thin parent layout that reuses PhoenixKit's header component without a sidebar.

**Tech Stack:** Elixir/Phoenix 1.8, LiveView 1.2, PhoenixKit 1.7.145 (Dashboard registry + LayoutWrapper), DaisyUI v5, Heroicons.

---

## Key facts (verified against deps)

- `config :phoenix_kit, :admin_dashboard_tabs` is a flat list of tab maps. A tab with
  `live_view: {Module, :index}` auto-generates `live <path>, Module, :index` inside
  `live_session :phoenix_kit_admin` (auth + admin layout auto-applied). Source:
  `deps/phoenix_kit/lib/phoenix_kit_web/integration.ex:401,494,702-741,831-835`.
- Tab map keys: `id` (atom), `label` (string), `icon` (heroicon string), `path`
  (absolute `/admin/...`), `live_view` ({Mod,:index}), `permission` (string),
  `priority` (int, lower = higher in list), `group` (atom), `parent` (atom, optional).
- Default PhoenixKit groups: `:admin_main` (priority 100), `:admin_modules` (500),
  `:admin_system` (900). To place trading **above** them, use a group with priority `< 100`.
- `app_layout` renders admin chrome when `current_path` is under `/admin`; otherwise it
  uses the parent layout `config :phoenix_kit, layout: {DashboardWeb.Layouts, :app}`
  (`deps/phoenix_kit/lib/phoenix_kit_web/components/layout_wrapper.ex`). Admin LiveViews
  must NOT call `app_layout` themselves (double-wrap guard) — they render plain content
  and assign `:url_path` for active-tab highlighting.
- Both app users are `Owner`/`Admin`; `permission: "dashboard"` is visible to them.

## File structure

- Modify: `config/config.exs` — add `:admin_dashboard_tabs` with trading tabs + a trading group.
- Modify: `apps/dashboard_web/lib/dashboard_web/router.ex` — delete `live_session :trading_app`; add `/app/*`→`/admin/*` redirects.
- Modify (7): `apps/dashboard_web/lib/dashboard_web/live/{trading,portfolio,orders,history,strategies,chains,settings}_live.ex` — drop custom-layout assumptions, set `url_path`, drop `current_path`/nav assigns.
- Modify: `apps/dashboard_web/lib/dashboard_web/components/layouts.ex` — slim `app/1` to reuse PhoenixKit header; remove `trading_nav_link/1`, `trading_nav_icon/1`.
- Delete: `components/layouts/trading_dashboard.html.heex`, `components/layouts/drawer.html.heex`, `components/layouts/public.html.heex`, `components/dashboard_nav.ex`.
- Verify only: `components/layouts/root.html.heex`.

---

## Task 0: Baseline snapshot

**Files:** none (capture current state)

- [ ] **Step 1: Confirm branch + clean tree**

Run: `cd /app && git rev-parse --abbrev-ref HEAD && git status --short`
Expected: branch `refactor/unify-layouts-navigation`, no uncommitted app changes (only this plan/spec).

- [ ] **Step 2: Snapshot current trading routes**

Run: `cd /app && mix phx.routes DashboardWeb.Router 2>/dev/null | grep -E "/app/|TradingLive|PortfolioLive|OrdersLive|HistoryLive|StrategiesLive|ChainsLive|SettingsLive"`
Expected: the seven `/app/*` live routes. Save the output to compare after.

- [ ] **Step 3: Baseline test run**

Run: `cd /app && MIX_ENV=test mix test 2>&1 | tail -5`
Expected: `0 failures` (81 tests). (Note: `MIX_ENV=test` is required — container exports `MIX_ENV=dev`.)

---

## Task 1: Register trading tabs (auto-generates admin routes)

**Files:**
- Modify: `config/config.exs`

- [ ] **Step 1: Add the trading tabs config**

In `config/config.exs`, after the existing `config :phoenix_kit, ... url_prefix: "/phoenix_kit"` block, add:

```elixir
# Trading navigation — injected into PhoenixKit's admin sidebar ABOVE the
# built-in groups (group priority < admin_main's 100). Each tab's `live_view`
# auto-generates its route inside the shared :phoenix_kit_admin live_session,
# so trading pages inherit PhoenixKit auth + admin chrome (header + sidebar).
config :phoenix_kit, :admin_dashboard_tabs, [
  # --- Trading group (top) ---
  %{
    id: :trading_chart,
    label: "Trading",
    icon: "hero-chart-bar",
    path: "/admin/trading",
    live_view: {DashboardWeb.TradingLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 10
  },
  %{
    id: :trading_portfolio,
    label: "Portfolio",
    icon: "hero-wallet",
    path: "/admin/portfolio",
    live_view: {DashboardWeb.PortfolioLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 11
  },
  %{
    id: :trading_orders,
    label: "Orders",
    icon: "hero-clipboard-document-list",
    path: "/admin/orders",
    live_view: {DashboardWeb.OrdersLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 12
  },
  %{
    id: :trading_history,
    label: "History",
    icon: "hero-clock",
    path: "/admin/history",
    live_view: {DashboardWeb.HistoryLive, :index},
    permission: "dashboard",
    group: :trading,
    priority: 13
  },
  # --- Automation group ---
  %{
    id: :trading_strategies,
    label: "Strategies",
    icon: "hero-cpu-chip",
    path: "/admin/strategies",
    live_view: {DashboardWeb.StrategiesLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 20
  },
  %{
    id: :trading_chains,
    label: "Chains",
    icon: "hero-link",
    path: "/admin/chains",
    live_view: {DashboardWeb.ChainsLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 21
  },
  # --- Accounts (Binance API keys) ---
  %{
    id: :trading_accounts,
    label: "Accounts",
    icon: "hero-key",
    path: "/admin/accounts",
    live_view: {DashboardWeb.SettingsLive, :index},
    permission: "dashboard",
    group: :trading_automation,
    priority: 22
  }
]
```

- [ ] **Step 2: Register the custom groups (so trading sits above PhoenixKit)**

Check whether group ordering needs explicit group definitions. Run:
`cd /app && grep -n "admin_dashboard_groups\|def default_groups\|Group{" deps/phoenix_kit/lib/phoenix_kit/dashboard/admin_tabs.ex deps/phoenix_kit/lib/phoenix_kit/dashboard/*.ex | head`
If a `:admin_dashboard_groups` config key exists, add it; otherwise groups are derived from tabs and ordered by the minimum tab `priority` in the group (trading priorities 10/20 < PhoenixKit's 100), which already places them on top. Document which mechanism applied in the commit message.

- [ ] **Step 3: Recompile so the route macro re-reads config**

Run: `cd /app && mix compile --force 2>&1 | tail -3`
Expected: compiles, no errors. (Routes are generated at compile time from config.)

- [ ] **Step 4: Verify routes were auto-generated**

Run: `cd /app && mix phx.routes DashboardWeb.Router 2>/dev/null | grep -E "TradingLive|PortfolioLive|OrdersLive|HistoryLive|StrategiesLive|ChainsLive|SettingsLive"`
Expected: each LiveView now appears at an `/admin/...` path (e.g. `/:locale/admin/trading` and/or `/admin/trading`) — NOT only `/app/*`. If nothing appears, the config wasn't picked up — re-check key name `:admin_dashboard_tabs` and `mix compile --force`.

- [ ] **Step 5: Commit**

```bash
cd /app && git add config/config.exs
git commit -m "feat(nav): register trading pages as PhoenixKit admin tabs"
```

---

## Task 1b: Register the Trading/Automation sidebar groups (added after Task 1 review)

**Why:** `:admin_dashboard_tabs` config registers tabs and auto-generates routes, but tabs whose `group:` is not a *registered* group are **dropped from the sidebar** (`TabHelpers.sorted_groups/2` filters to registered groups). There is no config key for admin groups — they must be registered at runtime. The public `PhoenixKit.Dashboard.register_groups/1` **overwrites** the group list (it does not merge), and PhoenixKit loads its default groups (`:admin_main` p100, `:admin_modules` p500, `:admin_system` p900) asynchronously in the registry's `handle_continue`. So we register a small supervised initializer that waits until defaults are present, then re-registers `current_groups ++ our_groups` (priorities 10/20 < 100 → above PhoenixKit).

**Files:**
- Create: `apps/dashboard_web/lib/dashboard_web/nav_init.ex`
- Modify: `apps/dashboard_web/lib/dashboard_web/application.ex`

- [ ] **Step 1: Create the initializer**

Create `apps/dashboard_web/lib/dashboard_web/nav_init.ex`:

```elixir
defmodule DashboardWeb.NavInit do
  @moduledoc """
  Registers the Trading/Automation sidebar groups into PhoenixKit's dashboard
  registry so the trading admin tabs (config :phoenix_kit, :admin_dashboard_tabs)
  render in the sidebar above PhoenixKit's built-in groups.

  PhoenixKit's public `register_groups/1` OVERWRITES the group list and loads its
  own defaults asynchronously, so we wait until the defaults (`:admin_main`) are
  present, then re-register `current ++ ours` (merge by id). Idempotent.
  """
  use GenServer
  require Logger

  alias PhoenixKit.Dashboard

  # priorities < admin_main's 100 => render above PhoenixKit groups
  @trading_groups [
    %{id: :trading, label: "Trading", priority: 10},
    %{id: :trading_automation, label: "Automation", priority: 20}
  ]

  def start_link(_), do: GenServer.start_link(__MODULE__, %{tries: 0}, name: __MODULE__)

  @impl true
  def init(state), do: {:ok, state, {:continue, :register}}

  @impl true
  def handle_continue(:register, state), do: do_register(state)

  @impl true
  def handle_info(:retry, state), do: do_register(state)

  defp do_register(state) do
    groups = Dashboard.get_groups()

    cond do
      Enum.any?(groups, &(&1.id == :trading)) ->
        {:noreply, state}

      Enum.any?(groups, &(&1.id == :admin_main)) ->
        missing = Enum.reject(@trading_groups, fn g -> Enum.any?(groups, &(&1.id == g.id)) end)
        if missing != [], do: Dashboard.register_groups(groups ++ missing)
        {:noreply, state}

      state.tries < 100 ->
        Process.send_after(self(), :retry, 100)
        {:noreply, %{state | tries: state.tries + 1}}

      true ->
        Logger.warning("[NavInit] PhoenixKit dashboard groups not loaded; trading nav groups skipped")
        {:noreply, state}
    end
  end
end
```

- [ ] **Step 2: Add it to the supervision tree AFTER `PhoenixKit.Supervisor`**

In `apps/dashboard_web/lib/dashboard_web/application.ex`, add `DashboardWeb.NavInit` to the `children` list immediately AFTER `PhoenixKit.Supervisor` (so the registry exists before it runs):

```elixir
    children = [
      PhoenixKit.Supervisor,
      DashboardWeb.NavInit,
      {Finch, [name: Swoosh.Finch]},
      DashboardWeb.Telemetry,
      DashboardWeb.Endpoint,
      {Oban, Application.get_env(:dashboard_web, Oban)}
    ]
```

- [ ] **Step 3: Compile**

Run: `cd /app && mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: EXIT 0.

- [ ] **Step 4: Verify groups register without wiping defaults (eval against a booted app)**

Run:
```bash
cd /app && cat > /tmp/navcheck.exs <<'EOF'
Application.ensure_all_started(:dashboard_web)
Process.sleep(800)
groups = PhoenixKit.Dashboard.get_groups() |> Enum.map(&{&1.id, &1.priority})
IO.inspect(groups, label: "groups")
ids = Enum.map(groups, &elem(&1, 0))
IO.puts(if Enum.all?([:trading, :trading_automation, :admin_main, :admin_modules, :admin_system], &(&1 in ids)), do: "OK: all groups present", else: "FAIL: missing groups")
EOF
mix run --no-start /tmp/navcheck.exs 2>&1 | tail -8
```
Expected: groups list includes `:trading` (10) and `:trading_automation` (20) **and** `:admin_main`/`:admin_modules`/`:admin_system` (defaults NOT wiped) → "OK: all groups present".

- [ ] **Step 5: Commit**

```bash
cd /app && git add apps/dashboard_web/lib/dashboard_web/nav_init.ex apps/dashboard_web/lib/dashboard_web/application.ex
git commit -m "feat(nav): register Trading/Automation sidebar groups above PhoenixKit"
```

---

## Task 2: Remove the old `/app` live_session and add redirects

Phoenix has **no built-in router redirect macro**, so we add a tiny controller that
issues 301s. (`Phoenix.Controller.redirect/2` is the real API.)

**Files:**
- Create: `apps/dashboard_web/lib/dashboard_web/controllers/legacy_redirect_controller.ex`
- Modify: `apps/dashboard_web/lib/dashboard_web/router.ex`

- [ ] **Step 1: Delete the trading live_session block**

Remove the entire `scope "/app", DashboardWeb do ... live_session :trading_app ... end` block (router.ex lines ~30-46) — these routes are now auto-generated under `/admin`.

- [ ] **Step 2: Create the redirect controller**

Create `apps/dashboard_web/lib/dashboard_web/controllers/legacy_redirect_controller.ex`:

```elixir
defmodule DashboardWeb.LegacyRedirectController do
  @moduledoc "Permanent redirects from legacy /app/* trading URLs to /admin/*."
  use DashboardWeb, :controller

  @map %{
    "trading" => "/admin/trading",
    "portfolio" => "/admin/portfolio",
    "orders" => "/admin/orders",
    "history" => "/admin/history",
    "strategies" => "/admin/strategies",
    "chains" => "/admin/chains",
    "accounts" => "/admin/accounts"
  }

  def show(conn, %{"page" => page}) when is_map_key(@map, page) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: Map.fetch!(@map, page))
    |> halt()
  end

  def show(conn, _params), do: redirect(conn, to: "/admin")
end
```

- [ ] **Step 3: Wire the redirect route**

In `router.ex`, inside the existing root `scope "/", DashboardWeb do pipe_through :browser ... end` (the one with `get "/", PageController, :home`), add:

```elixir
get "/app/:page", LegacyRedirectController, :show
```

- [ ] **Step 4: Compile + verify**

Run: `cd /app && mix compile 2>&1 | tail -3 && mix phx.routes DashboardWeb.Router 2>/dev/null | grep -E "/app/"`
Expected: compiles; `/app/:page` shows mapped to `DashboardWeb.LegacyRedirectController :show`; no `/app/*` live routes remain.

- [ ] **Step 5: Commit**

```bash
cd /app && git add apps/dashboard_web/lib/dashboard_web/router.ex apps/dashboard_web/lib/dashboard_web/controllers/legacy_redirect_controller.ex
git commit -m "refactor(router): drop /app trading live_session, redirect /app/* to /admin/*"
```

---

## Task 3: Adapt the 7 trading LiveViews to admin chrome

Each LiveView currently relied on the `trading_dashboard` layout and set `current_path: "/app/..."`. Inside the admin live_session the admin layout wraps them automatically; they must (a) set `:url_path` (used by `app_layout` for active-tab highlight) to the new `/admin/...` path, and (b) NOT reference the removed `DashboardWeb.Components.DashboardNav` or the trading layout.

Repeat Steps 1–4 below for EACH file, substituting the path:
`trading_live.ex`→`/admin/trading`, `portfolio_live.ex`→`/admin/portfolio`,
`orders_live.ex`→`/admin/orders`, `history_live.ex`→`/admin/history`,
`strategies_live.ex`→`/admin/strategies`, `chains_live.ex`→`/admin/chains`,
`settings_live.ex`→`/admin/accounts`.

- [ ] **Step 1: Find layout/nav coupling in the file**

Run (example for trading): `cd /app && grep -n "current_path\|DashboardNav\|trading_dashboard\|url_path\|page_title" apps/dashboard_web/lib/dashboard_web/live/trading_live.ex`
Expected: shows the `assign(current_path: "/app/trading")` line and any `DashboardNav` refs.

- [ ] **Step 2: Replace `current_path` assign with `url_path`**

Change `|> assign(current_path: "/app/trading")` to `|> assign(url_path: "/admin/trading")` (use the file's matching `/admin/...` path). If the file has no such assign, add `|> assign(:url_path, "/admin/trading")` in `mount/3`. Keep all existing business logic, PubSub subscriptions, and `page_title`.

- [ ] **Step 3: Remove any direct DashboardNav usage in the template**

If `grep` from Step 1 shows `DashboardWeb.Components.DashboardNav.*` calls in this LiveView's `render/1`, delete those nodes (the header/nav now comes from the admin layout). Trading page content stays.

- [ ] **Step 4: Compile this file's app**

Run: `cd /app && mix compile 2>&1 | tail -3`
Expected: compiles, no `undefined function`/`unused` errors referencing this file.

- [ ] **Step 5: Commit (after all 7 done)**

```bash
cd /app && git add apps/dashboard_web/lib/dashboard_web/live/
git commit -m "refactor(live): trading pages render inside PhoenixKit admin chrome"
```

---

## Task 4: Unify the public/blog header

**Files:**
- Modify: `apps/dashboard_web/lib/dashboard_web/components/layouts.ex`

- [ ] **Step 1: Inspect PhoenixKit's reusable header component**

Run: `cd /app && grep -n "def .*header\|def admin_nav\|def top_bar\|attr " deps/phoenix_kit/lib/phoenix_kit_web/components/admin_nav.ex | head -20`
Identify the public/guest-capable header function (and its required attrs) that PhoenixKit renders in `app_layout`. Note its name + attrs.

- [ ] **Step 2: Slim `Layouts.app/1` to reuse that header (keep the news icon)**

Rewrite the `def app(assigns)` body in `layouts.ex` so the `<header>` reuses the PhoenixKit header component identified in Step 1 (so blog header == admin header visually), keeping the brand/logo linking to `/news`. Keep the `<main>`/`<footer>` and the `inner_block`/`inner_content` dual-rendering already present. Remove `DashboardWeb.Components.DashboardNav.theme_switcher` / `public_user_menu` calls — use the PhoenixKit header's built-in theme/user controls instead. If the PhoenixKit header component is not safely reusable standalone, INSTEAD keep a minimal hand-rolled header that visually matches (logo→/news, `PhoenixKitWeb.Components.Core` theme toggle + login/user link) and note the decision in the commit.

- [ ] **Step 3: Remove `trading_nav_link/1` and `trading_nav_icon/1` from `layouts.ex`**

These were only used by `trading_dashboard.html.heex` (deleted in Task 5). Delete both function defs and their `@doc`/`attr` blocks.

- [ ] **Step 4: Compile**

Run: `cd /app && mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: compiles clean (no references to removed functions).

- [ ] **Step 5: Commit**

```bash
cd /app && git add apps/dashboard_web/lib/dashboard_web/components/layouts.ex
git commit -m "refactor(layout): unify public header with PhoenixKit, keep /news brand"
```

---

## Task 5: Delete dead layouts, nav, and the obsolete user-settings dashboard link

**Files:**
- Delete: `components/layouts/trading_dashboard.html.heex`, `components/layouts/drawer.html.heex`, `components/layouts/public.html.heex`, `components/dashboard_nav.ex`

- [ ] **Step 1: Confirm nothing else references them**

Run: `cd /app && grep -rn "DashboardNav\|trading_dashboard\|:drawer\|layouts/public\|/dashboard/settings" apps/dashboard_web/lib | grep -v "_build"`
Expected: only the files we're about to delete (and possibly `layouts.ex` `embed_templates "layouts/*"`, which is fine — it globs whatever remains). If a `*_live.ex` or template still references `/dashboard/settings` (the old Profile link), remove that link node.

- [ ] **Step 2: Delete the files**

```bash
cd /app && git rm \
  apps/dashboard_web/lib/dashboard_web/components/layouts/trading_dashboard.html.heex \
  apps/dashboard_web/lib/dashboard_web/components/layouts/drawer.html.heex \
  apps/dashboard_web/lib/dashboard_web/components/layouts/public.html.heex \
  apps/dashboard_web/lib/dashboard_web/components/dashboard_nav.ex
```

- [ ] **Step 3: Compile (catches any dangling reference)**

Run: `cd /app && mix compile --warnings-as-errors 2>&1 | tail -5`
Expected: compiles clean. If it fails with `DashboardNav` undefined, fix the referencing file (remove the call) and recompile.

- [ ] **Step 4: Commit**

```bash
cd /app && git commit -m "chore: remove custom layouts, dashboard_nav, obsolete user dashboard link"
```

---

## Task 6: Full verification

**Files:** none

- [ ] **Step 1: Clean compile**

Run: `cd /app && mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: EXIT 0, no warnings.

- [ ] **Step 2: Test suite**

Run: `cd /app && MIX_ENV=test mix test 2>&1 | tail -6`
Expected: `0 failures` (81 tests). Fix any regressions before continuing.

- [ ] **Step 3: Restart the dev server (clears caches, loads new routes)**

Run:
```bash
cd /app && tmux send-keys -t Binance:1.2 C-c && sleep 2 && \
  tmux send-keys -t Binance:1.2 'iex -S mix phx.server' Enter && sleep 42 && \
  tmux capture-pane -t Binance:1.2 -p -S -40 | grep -iE "Running DashboardWeb|\[error\]" | tail -5
```
Expected: "Running DashboardWeb.Endpoint ... at 0.0.0.0:4000", no `[error]`.

- [ ] **Step 4: Routes + protected-route wiring**

Run:
```bash
cd /app
mix phx.routes DashboardWeb.Router 2>/dev/null | grep -E "/admin/(trading|portfolio|orders|history|strategies|chains|accounts)"
for p in /admin/trading /admin/portfolio /admin/orders /admin/history /admin/strategies /admin/chains /admin/accounts; do
  curl -s -o /dev/null -w "%{http_code} $p\n" -m 10 "http://localhost:4000$p"
done
curl -s -o /dev/null -w "%{http_code} /app/trading (legacy)\n" -m 10 "http://localhost:4000/app/trading"
```
Expected: each `/admin/*` route present in the table; unauthenticated curls return `302`/`200` (redirect to login = correct auth wiring, not 404/500); `/app/trading` returns `301`/`302` to `/admin/trading`.

- [ ] **Step 5: Manual visual check (browser, logged in as Owner)**

Open `http://localhost:4000/admin/trading` while logged in and confirm:
1. PhoenixKit admin header + sidebar render (one unified header).
2. Trading + Automation + Accounts items appear at the TOP of the sidebar, above PhoenixKit items; active item highlights on each page.
3. Visit `/news` logged-out and logged-in: same header style, no sidebar, brand icon → `/news`, login (guest) / user-menu (authed).
4. Theme switch works on both. No leftover "Trading Blog" custom header / old drawer.

If the Playwright MCP is available, capture `/admin/trading` and `/news` screenshots instead of manual.

- [ ] **Step 6: Final commit (if any verification fixes were made)**

```bash
cd /app && git add -A && git commit -m "test: verify unified layout/navigation" || echo "nothing to commit"
```

---

## Done criteria (from spec)
- All 7 trading pages render inside PhoenixKit admin chrome; Trading/Automation/Accounts above PhoenixKit items; active highlight works.
- Blog/public + admin share one header; guest=login+theme+/news icon, authed=user-menu.
- `trading_dashboard`/`public`/`drawer` layouts + `dashboard_nav.ex` deleted; no dangling refs.
- Old `/app/*` redirect to `/admin/*`.
- `mix compile --warnings-as-errors` clean; `MIX_ENV=test mix test` green; server boots without errors.
