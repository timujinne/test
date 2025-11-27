# Dashboard Integration Guide

**Generated:** 2025-11-25 15:58:15
**Project:** DashboardWeb
**Module:** DashboardWebWeb

## Overview

Dashboard layout components have been generated for your Phoenix LiveView application.
This guide provides step-by-step instructions to integrate them into your project.

## Generated Files

✅ **Layout:** `lib/dashboard_web_web/components/layouts/dashboard.html.heex`
✅ **Components:** `lib/dashboard_web_web/components/dashboard_nav.ex`
✅ **LiveView:** `lib/dashboard_web_web/live/dashboard_live.ex`
✅ **Theme Hook:** Theme toggle code added to `assets/js/app.js`

## Integration Steps

### Step 1: Configure Router (REQUIRED)

Open `lib/dashboard_web_web/router.ex` and update your authenticated routes to use the dashboard layout.

**Find this section:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}] do

  live "/", HomeLive, :home
  # ... other routes
end
```

**Update to:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}],
  layout: {DashboardWebWeb.Layouts, :dashboard} do  # ← ADD THIS LINE

  live "/", DashboardLive, :index
  # Add more dashboard routes here
end
```

**Important:** All routes in this `live_session` block will use the dashboard layout.

### Step 2: Update JavaScript Hooks (REQUIRED)

The theme toggle hook has been added to `assets/js/app.js`.

**Verify LiveSocket configuration:**

Open `assets/js/app.js` and ensure the `Hooks` object is registered:

```javascript
// The Hooks object should be defined (added by generator)
let Hooks = { ThemeToggle };

// Your LiveSocket initialization should use hooks:
let liveSocket = new LiveSocket("/live", Socket, {
  // ... your existing configuration
  hooks: Hooks  // ← VERIFY THIS LINE EXISTS
})
```

**If you have existing hooks**, merge them:
```javascript
let Hooks = { ThemeToggle, ...yourExistingHooks };
```

### Step 3: Assign current_path in LiveViews

All LiveViews using the dashboard layout MUST assign `:current_path` to enable menu highlighting.

**In each LiveView's `mount/3` function:**

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:current_path, "/your-route")
   |> assign(:page_title, "Page Title")}
end
```

**For DashboardLive**, this is already done (`:current_path` set to `"/"`).

### Step 4: Customize Navigation Menu

Edit the sidebar menu in `lib/dashboard_web_web/components/layouts/dashboard.html.heex`:

**Find the navigation section** (around line 73):

```heex
<nav class="menu p-4 space-y-2 mt-16 lg:mt-0">
  <.nav_item href="/" icon="home" label="Dashboard" current_path={@current_path} />

  <%!-- ADD YOUR MENU ITEMS HERE --%>
</nav>
```

**Add your application routes:**

```heex
<%!-- Example menu items --%>
<.nav_item href="/films" icon="film" label="Films" current_path={@current_path} />
<.nav_item href="/translations" icon="translation" label="Translations" current_path={@current_path} />
<.nav_item href="/settings" icon="settings" label="Settings" current_path={@current_path} />
```

**Available icons:** `home`, `film`, `translation`, `stream`, `settings`

See `DASHBOARD_SETUP.md` for instructions on adding custom icons.

### Step 5: Update Dashboard Content

The generated dashboard in `lib/dashboard_web_web/live/dashboard_live.ex` contains placeholder content.

**Customize with your actual data:**

```elixir
def mount(_params, _session, socket) do
  # Load your application data
  stats = load_dashboard_statistics()

  {:ok,
   socket
   |> assign(:page_title, "Dashboard")
   |> assign(:current_path, "/")
   |> assign(:stats, stats)}
end
```

Then update the template to display your stats.

## Verification Checklist

Start your Phoenix server and verify everything works:

```bash
mix phx.server
```

Visit http://localhost:4000 and check:

- [ ] Dashboard layout displays with sidebar
- [ ] Navigation menu shows "Dashboard" item
- [ ] Dashboard item is highlighted (active state)
- [ ] Theme switcher works (click sun/moon icon)
- [ ] User dropdown shows your email
- [ ] Logout button works
- [ ] Mobile: burger menu opens/closes sidebar
- [ ] Desktop: sidebar is visible by default
- [ ] Sidebar can be toggled with burger menu

## Troubleshooting

### Sidebar not showing
- **Check router**: Ensure `layout: {DashboardWebWeb.Layouts, :dashboard}` is added
- **Check route**: Verify the route is inside the authenticated `live_session`
- **Check compilation**: Run `mix compile` to check for errors

### Theme not persisting
- **Check checkbox**: Verify `phx-hook="ThemeToggle"` attribute exists
- **Check LiveSocket**: Ensure `hooks: Hooks` is in LiveSocket initialization
- **Check browser console**: Look for JavaScript errors

### Menu item not highlighted
- **Check current_path**: Ensure `:current_path` is assigned in `mount/3`
- **Check route match**: The `href` must exactly match `:current_path`

### Compilation errors
- **Check module names**: All modules should use `{web_module}` prefix
- **Check imports**: Verify `{web_module}.CoreComponents` is imported
- **Run**: `mix deps.get && mix compile`

## Next Steps

1. **Add more routes** to your router using the dashboard layout
2. **Customize menu items** for your application's features
3. **Update dashboard content** with real data and widgets
4. **Add nested submenus** if needed (see DASHBOARD_SETUP.md)
5. **Customize styling** via Tailwind utility classes
6. **Deploy** and test in production

## Additional Resources

- **Full customization guide:** `DASHBOARD_SETUP.md`
- **DaisyUI documentation:** https://daisyui.com/
- **Phoenix LiveView guides:** https://hexdocs.pm/phoenix_live_view/

---

**Generated by Dashboard Generator**
For issues or questions, refer to the skill documentation.
