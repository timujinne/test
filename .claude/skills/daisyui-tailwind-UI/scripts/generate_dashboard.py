#!/usr/bin/env python3
"""
Dashboard Generator Script for DaisyUI + Phoenix LiveView

This script generates a complete Dashboard layout structure with:
- DaisyUI drawer-based layout with sidebar navigation
- Toggle sidebar button (works on all screen sizes)
- Theme switcher (Light/Dark)
- User dropdown with logout
- PhoenixKit authentication integration

Usage:
    python3 generate_dashboard.py [--project-root PATH]

The script will:
1. Generate dashboard layout component
2. Create navigation components module
3. Create basic dashboard LiveView (if doesn't exist)
4. Update router configuration
5. Generate LLM customization instructions
"""

import os
import sys
import argparse
from pathlib import Path
from datetime import datetime

# ============================================================================
# TEMPLATES
# ============================================================================

DASHBOARD_LAYOUT_TEMPLATE = '''<%!-- Dashboard Layout with Drawer --%>
<div class="drawer lg:drawer-open h-screen">
  <%!-- Toggle checkbox for drawer --%>
  <input id="dashboard-drawer" type="checkbox" class="drawer-toggle" />

  <%!-- Main content area --%>
  <div class="drawer-content flex flex-col h-full">
    <%!-- Top Navigation Bar --%>
    <header class="navbar bg-base-100 shadow-md border-b border-base-300 sticky top-0 z-40">
      <div class="flex-none">
        <%!-- Toggle sidebar button --%>
        <label for="dashboard-drawer" class="btn btn-square btn-ghost drawer-button">
          <svg
            class="w-6 h-6"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 12h16M4 18h16"
            />
          </svg>
        </label>
      </div>

      <div class="flex-1">
        <a href="/" class="btn btn-ghost text-xl">{display_name}</a>
      </div>

      <div class="flex-none gap-2">
        <%!-- Theme Switcher --%>
        <.theme_switcher />

        <%!-- User Dropdown --%>
        <.user_dropdown scope={{@phoenix_kit_current_scope}} />
      </div>
    </header>

    <%!-- Page Content --%>
    <main class="flex-1 overflow-y-auto p-6">
      <.flash_group flash={{@flash}} />
      {{@inner_content}}
    </main>
  </div>

  <%!-- Sidebar --%>
  <div class="drawer-side z-30">
    <label
      for="dashboard-drawer"
      aria-label="close sidebar"
      class="drawer-overlay"
    >
    </label>
    <aside class="min-h-full w-64 bg-base-100 border-r border-base-300">
      <%!-- Navigation Menu --%>
      <nav class="menu p-4 space-y-2 mt-16 lg:mt-0">
        <.nav_item href="/" icon="home" label="Dashboard" current_path={{@current_path}} />
        <%!-- Add more nav items here --%>
      </nav>
    </aside>
  </div>
</div>
'''

DASHBOARD_NAV_TEMPLATE = '''defmodule {web_module}.Components.DashboardNav do
  @moduledoc """
  Dashboard navigation components for DaisyUI-based layout.

  Provides reusable navigation components including:
  - Navigation items with active state
  - User dropdown
  - Theme switcher
  """

  use Phoenix.Component
  import {web_module}.CoreComponents
  import Phoenix.HTML, only: [raw: 1]
  alias PhoenixKit.Users.Auth.Scope

  @doc """
  Renders a navigation item with icon and label.

  ## Examples

      <.nav_item href="/" icon="home" label="Dashboard" current_path={{@current_path}} />
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, default: ""

  def nav_item(assigns) do
    assigns = assign(assigns, :active, assigns.current_path == assigns.href)

    ~H"""
    <li>
      <.link
        href={{@href}}
        class={{[
          "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
          @active && "bg-primary text-primary-content font-semibold",
          !@active && "hover:bg-base-200"
        ]}}
      >
        <.nav_icon name={{@icon}} />
        <span>{{@label}}</span>
      </.link>
    </li>
    """
  end

  @doc """
  Renders an icon for navigation items.
  """
  attr :name, :string, required: true

  def nav_icon(assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      {{raw(icon_path(@name))}}
    </svg>
    """
  end

  # Icon SVG paths
  defp icon_path("home") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
    """
  end

  defp icon_path("film") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
    """
  end

  defp icon_path("translation") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
    """
  end

  defp icon_path("stream") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
    """
  end

  defp icon_path("settings") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    """
  end

  defp icon_path(_), do: ""

  @doc """
  Renders the user dropdown menu.
  """
  attr :scope, :any, required: true

  def user_dropdown(assigns) do
    assigns =
      assigns
      |> assign_new(:email, fn -> Scope.user_email(assigns.scope) end)
      |> assign_new(:first_letter, fn ->
        email = Scope.user_email(assigns.scope)
        if email, do: String.upcase(String.first(email)), else: "U"
      end)

    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-circle avatar placeholder"
      >
        <div class="w-10 rounded-full bg-primary text-primary-content">
          <span class="text-lg font-semibold">{{@first_letter}}</span>
        </div>
      </div>
      <ul
        tabindex="0"
        class="menu menu-sm dropdown-content mt-3 z-[60] p-2 shadow-xl bg-base-100 rounded-box w-52 border border-base-300"
      >
        <li class="menu-title px-4 py-2">
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium truncate">{{@email}}</span>
          </div>
        </li>
        <div class="divider my-0"></div>
        <li>
          <.link href="/users/settings" class="flex items-center gap-2">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
              />
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
              />
            </svg>
            Settings
          </.link>
        </li>
        <li>
          <.link href="/users/log_out" method="delete" class="flex items-center gap-2">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
              />
            </svg>
            Log Out
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders the theme switcher toggle.

  Uses pure CSS approach with DaisyUI themes.
  """
  def theme_switcher(assigns) do
    ~H"""
    <label class="swap swap-rotate">
      <%!-- Hidden checkbox controls the state --%>
      <input
        type="checkbox"
        class="theme-controller"
        value="dark"
        phx-hook="ThemeToggle"
        id="theme-toggle"
      />

      <%!-- Sun icon (light mode) --%>
      <svg
        class="swap-off fill-current w-6 h-6"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
      >
        <path d="M5.64,17l-.71.71a1,1,0,0,0,0,1.41,1,1,0,0,0,1.41,0l.71-.71A1,1,0,0,0,5.64,17ZM5,12a1,1,0,0,0-1-1H3a1,1,0,0,0,0,2H4A1,1,0,0,0,5,12Zm7-7a1,1,0,0,0,1-1V3a1,1,0,0,0-2,0V4A1,1,0,0,0,12,5ZM5.64,7.05a1,1,0,0,0,.7.29,1,1,0,0,0,.71-.29,1,1,0,0,0,0-1.41l-.71-.71A1,1,0,0,0,4.93,6.34Zm12,.29a1,1,0,0,0,.7-.29l.71-.71a1,1,0,1,0-1.41-1.41L17,5.64a1,1,0,0,0,0,1.41A1,1,0,0,0,17.66,7.34ZM21,11H20a1,1,0,0,0,0,2h1a1,1,0,0,0,0-2Zm-9,8a1,1,0,0,0-1,1v1a1,1,0,0,0,2,0V20A1,1,0,0,0,12,19ZM18.36,17A1,1,0,0,0,17,18.36l.71.71a1,1,0,0,0,1.41,0,1,1,0,0,0,0-1.41ZM12,6.5A5.5,5.5,0,1,0,17.5,12,5.51,5.51,0,0,0,12,6.5Zm0,9A3.5,3.5,0,1,1,15.5,12,3.5,3.5,0,0,1,12,15.5Z" />
      </svg>

      <%!-- Moon icon (dark mode) --%>
      <svg
        class="swap-on fill-current w-6 h-6"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
      >
        <path d="M21.64,13a1,1,0,0,0-1.05-.14,8.05,8.05,0,0,1-3.37.73A8.15,8.15,0,0,1,9.08,5.49a8.59,8.59,0,0,1,.25-2A1,1,0,0,0,8,2.36,10.14,10.14,0,1,0,22,14.05,1,1,0,0,0,21.64,13Zm-9.5,6.69A8.14,8.14,0,0,1,7.08,5.22v.27A10.15,10.15,0,0,0,17.22,15.63a9.79,9.79,0,0,0,2.1-.22A8.11,8.11,0,0,1,12.14,19.73Z" />
      </svg>
    </label>
    """
  end
end
'''

DASHBOARD_LIVE_TEMPLATE = '''defmodule {web_module}.DashboardLive do
  @moduledoc """
  Main Dashboard LiveView page.

  This is a placeholder dashboard. Customize it with your own content,
  widgets, statistics, or any other information you want to display
  on the main dashboard page.
  """

  use {web_module}, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {{:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_path, "/")}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto">
      <h1 class="text-3xl font-bold mb-6">Welcome to {display_name} Dashboard</h1>

      <%!-- Stats Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div class="stats shadow">
          <div class="stat">
            <div class="stat-title">Total Films</div>
            <div class="stat-value text-primary">0</div>
            <div class="stat-desc">Add your first film</div>
          </div>
        </div>

        <div class="stats shadow">
          <div class="stat">
            <div class="stat-title">Dialogues</div>
            <div class="stat-value text-secondary">0</div>
            <div class="stat-desc">No dialogues yet</div>
          </div>
        </div>

        <div class="stats shadow">
          <div class="stat">
            <div class="stat-title">Translations</div>
            <div class="stat-value text-accent">0</div>
            <div class="stat-desc">Start translating</div>
          </div>
        </div>

        <div class="stats shadow">
          <div class="stat">
            <div class="stat-title">Live Streams</div>
            <div class="stat-value">0</div>
            <div class="stat-desc">No active streams</div>
          </div>
        </div>
      </div>

      <%!-- Welcome Card --%>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Getting Started</h2>
          <p>
            This is your dashboard. Customize this page to show relevant information
            for your translation workflow.
          </p>
          <div class="card-actions justify-end mt-4">
            <button class="btn btn-primary">Get Started</button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
'''

THEME_HOOK_JS = '''// Theme Toggle Hook for Phoenix LiveView
// Handles theme switching between light and dark modes

export const ThemeToggle = {
  mounted() {
    // Load saved theme from localStorage
    const savedTheme = localStorage.getItem('theme') || 'light';
    this.setTheme(savedTheme);

    // Set initial checkbox state
    if (savedTheme === 'dark') {
      this.el.checked = true;
    }

    // Listen for changes
    this.el.addEventListener('change', (e) => {
      const theme = e.target.checked ? 'dark' : 'light';
      this.setTheme(theme);
    });
  },

  setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }
};
'''

SETUP_INSTRUCTIONS = '''# Dashboard Setup Instructions

This guide explains how to customize and extend the generated Dashboard layout.

## Generated Files

1. **Layout**: `lib/ftvplus_server_web/components/layouts/dashboard.html.heex`
   - Main dashboard layout with drawer navigation
   - Header with theme switcher and user dropdown
   - Sidebar navigation menu

2. **Components**: `lib/ftvplus_server_web/components/dashboard_nav.ex`
   - Reusable navigation components
   - Icon helpers
   - User dropdown and theme switcher

3. **LiveView**: `lib/ftvplus_server_web/live/dashboard_live.ex`
   - Main dashboard page (only created if didn't exist)
   - Placeholder content with stats cards

4. **Router**: `lib/ftvplus_server_web/router.ex`
   - Updated to use dashboard layout for protected routes

5. **JavaScript Hook**: `assets/js/app.js`
   - Theme toggle functionality

## Customization Guide

### Adding New Menu Items

Edit `lib/ftvplus_server_web/components/layouts/dashboard.html.heex`:

```heex
<nav class="menu p-4 space-y-2 mt-16 lg:mt-0">
  <.nav_item href="/" icon="home" label="Dashboard" current_path={@current_path} />

  <%!-- Add your new menu items here --%>
  <.nav_item href="/films" icon="film" label="Films" current_path={@current_path} />
  <.nav_item href="/translations" icon="translation" label="Translations" current_path={@current_path} />
  <.nav_item href="/streams" icon="stream" label="Live Streams" current_path={@current_path} />

  <%!-- Settings section with divider --%>
  <div class="divider"></div>
  <.nav_item href="/settings" icon="settings" label="Settings" current_path={@current_path} />
</nav>
```

### Available Icons

Built-in icons in `dashboard_nav.ex`:
- `home` - Dashboard
- `film` - Films/Movies
- `translation` - Translations
- `stream` - Live Streams
- `settings` - Settings

### Adding Custom Icons

Edit `lib/ftvplus_server_web/components/dashboard_nav.ex`:

```elixir
defp icon_path("your-icon-name") do
  """
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
        d="YOUR_SVG_PATH_HERE" />
  """
end
```

Get SVG paths from [Heroicons](https://heroicons.com/).

### Creating Nested Submenus

For collapsible submenus, use the `<details>` element:

```heex
<li>
  <details open>
    <summary>
      <.nav_icon name="film" />
      <span>Films</span>
    </summary>
    <ul class="ml-4">
      <.nav_item href="/films/all" icon="film" label="All Films" current_path={@current_path} />
      <.nav_item href="/films/new" icon="film" label="Add Film" current_path={@current_path} />
    </ul>
  </details>
</li>
```

### Changing Project Title

Edit the header in `dashboard.html.heex`:

```heex
<div class="flex-1">
  <a href="/" class="btn btn-ghost text-xl">Your Project Name</a>
</div>
```

### Adding More Themes

To add additional DaisyUI themes beyond Light/Dark:

1. Edit `tailwind.config.js`:

```javascript
module.exports = {
  daisyui: {
    themes: ["light", "dark", "cupcake", "cyberpunk"],
  },
}
```

2. Update the theme switcher in `dashboard_nav.ex` to include a dropdown with all themes.

### Customizing Dashboard Content

Edit `lib/ftvplus_server_web/live/dashboard_live.ex`:

```elixir
def mount(_params, _session, socket) do
  # Fetch your data
  films_count = MyApp.Films.count_films()

  {:ok,
   socket
   |> assign(:page_title, "Dashboard")
   |> assign(:current_path, "/")
   |> assign(:films_count, films_count)}
end
```

Then update the template to display your data.

### Adding Widgets

Create reusable widget components:

```elixir
# In dashboard_nav.ex or separate file
def stat_card(assigns) do
  ~H"""
  <div class="stats shadow">
    <div class="stat">
      <div class="stat-title">{@title}</div>
      <div class="stat-value text-primary">{@value}</div>
      <div class="stat-desc">{@description}</div>
    </div>
  </div>
  """
end
```

Use in your LiveView:

```heex
<.stat_card title="Total Films" value={@films_count} description="Active films" />
```

### Responsive Behavior

The sidebar is:
- **Desktop (lg and up)**: Always visible by default (`lg:drawer-open`)
- **Mobile/Tablet**: Hidden, opens via burger menu button
- **Toggle**: The burger menu button toggles sidebar on all screen sizes

To change this behavior, modify the drawer classes in `dashboard.html.heex`.

### Using with Different LiveViews

All LiveViews using the dashboard layout automatically get:
- Sidebar navigation
- Header with user menu
- Theme switcher
- Responsive drawer

Just ensure your route uses the `:require_authenticated_user` live_session.

### Theme Persistence

Themes are saved to `localStorage` with the key `"theme"`.

The `ThemeToggle` hook in `assets/js/app.js` handles:
- Loading saved theme on page load
- Saving theme changes
- Applying theme to `<html data-theme="...">`

### Styling Customization

Override DaisyUI component styles in `assets/css/app.css`:

```css
/* Custom dashboard styles */
.drawer-side {
  /* Sidebar customization */
}

.navbar {
  /* Header customization */
}
```

Or use Tailwind utility classes directly in the templates.

## Common Tasks

### Task: Add a Films Management Page

1. Create LiveView:

```bash
mix phx.gen.live Films Film films title:string year:integer
```

2. Add to router in the authenticated scope:

```elixir
live "/films", FilmLive.Index, :index
live "/films/new", FilmLive.Index, :new
```

3. Add menu item (see "Adding New Menu Items" above)

### Task: Create a Section Divider in Menu

```heex
<div class="divider"></div>
<li class="menu-title"><span>Section Name</span></li>
```

### Task: Add Badge to Menu Item

```heex
<.link href={@href} class="...">
  <.nav_icon name={@icon} />
  <span>{@label}</span>
  <span class="badge badge-primary badge-sm">New</span>
</.link>
```

### Task: Make Sidebar Collapsible on Desktop

Remove `lg:drawer-open` from the drawer div in `dashboard.html.heex`:

```heex
<div class="drawer h-full">  <%!-- removed: lg:drawer-open --%>
```

Now the burger menu button will toggle sidebar on all screen sizes.

## Troubleshooting

### Sidebar Not Toggling

Check that:
1. The checkbox `id="dashboard-drawer"` matches the label's `for` attribute
2. The `drawer-toggle` class is on the checkbox
3. The `drawer-button` class is on the burger menu button

### Theme Not Persisting

Verify:
1. The `ThemeToggle` hook is imported in `assets/js/app.js`
2. The hook is registered on the LiveSocket
3. The checkbox has `phx-hook="ThemeToggle"`

### Menu Active State Not Working

Ensure `@current_path` is assigned in your LiveView's `mount/3`:

```elixir
assign(socket, :current_path, socket.view |> to_string() |> String.replace("Elixir.", ""))
```

Or pass the actual path from the router.

## Next Steps

- Customize the dashboard content with real data
- Add more menu items for your application's features
- Create additional widgets and components
- Implement role-based menu visibility
- Add breadcrumbs for nested pages

Enjoy your new Dashboard layout! 🚀
'''

INTEGRATION_INSTRUCTIONS = '''# Dashboard Integration Guide

**Generated:** {timestamp}
**Project:** {display_name}
**Module:** {web_module}

## Overview

Dashboard layout components have been generated for your Phoenix LiveView application.
This guide provides step-by-step instructions to integrate them into your project.

## Generated Files

✅ **Layout:** `lib/{app_name}_web/components/layouts/dashboard.html.heex`
✅ **Components:** `lib/{app_name}_web/components/dashboard_nav.ex`
✅ **LiveView:** `lib/{app_name}_web/live/dashboard_live.ex`
✅ **Theme Hook:** Theme toggle code added to `assets/js/app.js`

## Integration Steps

### Step 1: Configure Router (REQUIRED)

Open `lib/{app_name}_web/router.ex` and update your authenticated routes to use the dashboard layout.

**Find this section:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}}] do

  live "/", HomeLive, :home
  # ... other routes
end
```

**Update to:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}}],
  layout: {{{web_module}.Layouts, :dashboard}} do  # ← ADD THIS LINE

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
let Hooks = {{ ThemeToggle }};

// Your LiveSocket initialization should use hooks:
let liveSocket = new LiveSocket("/live", Socket, {{
  // ... your existing configuration
  hooks: Hooks  // ← VERIFY THIS LINE EXISTS
}})
```

**If you have existing hooks**, merge them:
```javascript
let Hooks = {{ ThemeToggle, ...yourExistingHooks }};
```

### Step 3: Assign current_path in LiveViews

All LiveViews using the dashboard layout MUST assign `:current_path` to enable menu highlighting.

**In each LiveView's `mount/3` function:**

```elixir
def mount(_params, _session, socket) do
  {{:ok,
   socket
   |> assign(:current_path, "/your-route")
   |> assign(:page_title, "Page Title")}}
end
```

**For DashboardLive**, this is already done (`:current_path` set to `"/"`).

### Step 4: Customize Navigation Menu

Edit the sidebar menu in `lib/{app_name}_web/components/layouts/dashboard.html.heex`:

**Find the navigation section** (around line 73):

```heex
<nav class="menu p-4 space-y-2 mt-16 lg:mt-0">
  <.nav_item href="/" icon="home" label="Dashboard" current_path={{@current_path}} />

  <%!-- ADD YOUR MENU ITEMS HERE --%>
</nav>
```

**Add your application routes:**

```heex
<%!-- Example menu items --%>
<.nav_item href="/films" icon="film" label="Films" current_path={{@current_path}} />
<.nav_item href="/translations" icon="translation" label="Translations" current_path={{@current_path}} />
<.nav_item href="/settings" icon="settings" label="Settings" current_path={{@current_path}} />
```

**Available icons:** `home`, `film`, `translation`, `stream`, `settings`

See `DASHBOARD_SETUP.md` for instructions on adding custom icons.

### Step 5: Update Dashboard Content

The generated dashboard in `lib/{app_name}_web/live/dashboard_live.ex` contains placeholder content.

**Customize with your actual data:**

```elixir
def mount(_params, _session, socket) do
  # Load your application data
  stats = load_dashboard_statistics()

  {{:ok,
   socket
   |> assign(:page_title, "Dashboard")
   |> assign(:current_path, "/")
   |> assign(:stats, stats)}}
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
- **Check router**: Ensure `layout: {{{web_module}.Layouts, :dashboard}}` is added
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
- **Check module names**: All modules should use `{{web_module}}` prefix
- **Check imports**: Verify `{{web_module}}.CoreComponents` is imported
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
'''

LLM_INTEGRATION_CHECKLIST = '''# Dashboard Integration Checklist for LLM

**Generated:** {timestamp}
**Project:** {display_name}
**Module:** {web_module}

## Quick Integration Checklist

Use this checklist when integrating the generated dashboard into a Phoenix LiveView project.

### ✅ Step 1: Verify Generated Files

Check that these files were created successfully:

- [ ] `lib/{app_name}_web/components/layouts/dashboard.html.heex` - Dashboard partial layout (NO <html>, <head>, <body> tags)
- [ ] `lib/{app_name}_web/components/dashboard_nav.ex` - Navigation components
- [ ] `assets/js/app.js` - Contains ThemeToggle hook

**IMPORTANT:** Dashboard layout is a **partial layout**, not a full HTML document. The root.html.heex provides the HTML wrapper.

### ✅ Step 2: Update Root Layout

**File:** `lib/{app_name}_web/components/layouts/root.html.heex`

Add required classes for dashboard to work properly:

```heex
<!DOCTYPE html>
<html lang="en" class="h-full [scrollbar-gutter:stable]">  <!-- ← ADD h-full -->
  <head>
    <!-- ... head content ... -->
  </head>
  <body class="h-full bg-base-200">  <!-- ← ADD h-full and bg-base-200 -->
    {{@inner_content}}
  </body>
</html>
```

**Why:** Dashboard uses `h-screen` which requires parent elements to have `h-full` for proper height.

### ✅ Step 3: Configure layouts.ex

The layouts module MUST have a `dashboard/1` function that wraps the generated template.

**File:** `lib/{app_name}_web/components/layouts.ex`

**Required code:**
```elixir
# Define dashboard/1 wrapper to call generated template
def dashboard(assigns) do
  # Ensure current_path is set for navigation highlighting
  assigns = assign_new(assigns, :current_path, fn -> "/" end)
  dashboard_template(assigns)
end
```

**Why:** Phoenix's `embed_templates` creates `dashboard_template/1`, but the router expects `dashboard/1`.

### ✅ Step 4: Update Router Configuration

**File:** `lib/{app_name}_web/router.ex`

**Find the authenticated live_session:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}}] do

  live "/", HomeLive, :home
end
```

**Add layout parameter:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}}],
  layout: {{{web_module}.Layouts, :dashboard}} do  # ← ADD THIS

  live "/", HomeLive, :home
end
```

**Critical:** This makes the dashboard layout wrap all routes in this live_session.

### ✅ Step 5: Configure LiveSocket Hooks

**File:** `assets/js/app.js`

**IMPORTANT:** Code must be in the correct order:
1. Define ThemeToggle hook FIRST
2. Create Hooks object
3. Create LiveSocket with Hooks
4. THEN call liveSocket.connect()

**Correct order:**

```javascript
// Theme Toggle Hook (BEFORE LiveSocket definition)
export const ThemeToggle = {{
  mounted() {{
    const savedTheme = localStorage.getItem('theme') || 'light';
    this.setTheme(savedTheme);
    if (savedTheme === 'dark') {{ this.el.checked = true; }}
    this.el.addEventListener('change', (e) => {{
      this.setTheme(e.target.checked ? 'dark' : 'light');
    }});
  }},
  setTheme(theme) {{
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }}
}};

// Create Hooks object
let Hooks = {{ ThemeToggle }};

// Initialize LiveSocket with hooks
let liveSocket = new LiveSocket("/live", Socket, {{
  longPollFallbackMs: 2500,
  params: {{ _csrf_token: csrfToken }},
  hooks: Hooks  // ← MUST BE HERE
}});

// Connect AFTER LiveSocket is defined
liveSocket.connect();

// Expose on window
window.liveSocket = liveSocket;
```

**If you have existing hooks:**
```javascript
let Hooks = {{ ThemeToggle, ...existingHooks }};
```

**Common error:** `Cannot read properties of undefined (reading 'connect')` means `liveSocket.connect()` is called BEFORE `liveSocket` is defined. Fix by moving the code to the correct order above.

### ✅ Step 6: Set Required Assigns in LiveViews

**Every LiveView** using the dashboard layout MUST provide these assigns:

**Required assigns:**
- `:current_path` - For menu item highlighting (e.g., `"/"`)
- `:page_title` - For page title in header (e.g., `"Dashboard"`)

**Example in LiveView's mount/3:**
```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(current_path: "/")
    |> assign(page_title: "Dashboard")
    # ... your other assigns

  {{:ok, socket}}
end
```

**Common error if missing:** `KeyError: key :page_title not found` or `key :current_path not found`

### ✅ Step 7: Verify Compilation

Run these commands to ensure everything compiles:

```bash
# Compile Elixir code
mix compile

# Check for warnings
mix compile --warnings-as-errors

# Start server
mix phx.server
```

**Expected result:** Server starts without errors, visit `http://localhost:4000/`

### ✅ Step 8: Test Dashboard Features

**Test these features:**

- [ ] **Login** - Can authenticate and reach dashboard
- [ ] **Sidebar** - Visible on desktop, toggles on mobile
- [ ] **Hamburger menu** - Opens AND closes sidebar when clicked
- [ ] **Theme toggle** - Switches between light/dark mode
- [ ] **User dropdown** - Shows user email/name and logout button
- [ ] **Navigation highlight** - Current page is highlighted in menu
- [ ] **Logout** - Successfully logs out and redirects

### ⚠️ Common Issues and Fixes

#### Issue: "key :csrf_token not found"
**Fix:** Dashboard layout should use `get_csrf_token()` function, not `@csrf_token` assign
```heex
<!-- Correct: -->
<meta name="csrf-token" content={{get_csrf_token()}} />

<!-- Wrong: -->
<meta name="csrf-token" content={{@csrf_token}} />
```

#### Issue: "key :page_title not found"
**Fix:** Add `:page_title` assign in your LiveView's mount/3:
```elixir
assign(socket, page_title: "Dashboard")
```

#### Issue: Unused import warning for CoreComponents
**Fix:** Remove unused import from `dashboard_nav.ex`:
```elixir
# Remove this line if not using CoreComponents:
import {{web_module}}.CoreComponents
```

#### Issue: Sidebar doesn't toggle on mobile
**Fix:** Verify the checkbox ID matches the label's `for` attribute:
```heex
<input id="dashboard-drawer" type="checkbox" class="drawer-toggle" />
<label for="dashboard-drawer" class="btn btn-square btn-ghost drawer-button">
```

#### Issue: Theme doesn't persist after refresh
**Fix:** Ensure ThemeToggle hook is registered on LiveSocket (see Step 4)

#### Issue: 404 errors for app.js and app.css
**Fix:** Ensure asset paths match your esbuild/tailwind output configuration.
**Default Phoenix paths:**
- CSS: `/assets/css/app.css` (not `/assets/app.css`)
- JS: `/assets/js/app.js` (not `/assets/app.js`)

**Verify in dashboard layout:**
```heex
<link phx-track-static rel="stylesheet" href={{~p"/assets/css/app.css"}} />
<script defer phx-track-static type="text/javascript" src={{~p"/assets/js/app.js"}}>
```

#### Issue: "Cannot read properties of undefined (reading 'connect')"
**Fix:** This means `liveSocket.connect()` is called BEFORE `liveSocket` is defined.
**Solution:** Reorder code in `assets/js/app.js`:
1. Define ThemeToggle hook first
2. Create Hooks object
3. Define `let liveSocket = new LiveSocket(...)`
4. THEN call `liveSocket.connect()`

See Step 5 above for complete correct code order.

#### Issue: "Cannot bind multiple views to the same DOM element"
**Fix:** Dashboard layout is a full HTML document but should be a **partial layout**.
**Solution:** Dashboard layout must NOT contain `<!DOCTYPE html>`, `<html>`, `<head>`, or `<body>` tags.

**Correct structure:**
```heex
<%!-- dashboard.html.heex should start with: --%>
<%!-- Dashboard Layout with Drawer --%>
<div class="drawer lg:drawer-open h-screen">
  <!-- ... dashboard content ... -->
</div>
<%!-- NO </body> or </html> tags! --%>
```

**Root layout provides HTML wrapper:**
- `root.html.heex` has `<html>`, `<head>`, `<body>`
- `dashboard.html.heex` contains ONLY the drawer structure
- Root layout's `{{@inner_content}}` renders dashboard content

Also ensure `root.html.heex` has required classes:
```heex
<html lang="en" class="h-full [scrollbar-gutter:stable]">
  <body class="h-full bg-base-200">
```

#### Issue: Theme switcher shows as Input Box instead of toggle
**Fix:** The theme switcher label should NOT have button classes.
**Problem:** `<label class="swap swap-rotate btn btn-ghost btn-circle">` causes checkbox to be visible.
**Solution:** Remove button classes from label in `dashboard_nav.ex`:

```elixir
# Correct:
<label class="swap swap-rotate">

# Wrong:
<label class="swap swap-rotate btn btn-ghost btn-circle">
```

**Why:** DaisyUI's swap component uses CSS to hide the checkbox and show/hide icons based on checkbox state. Adding button classes interferes with this styling and makes the input visible.

### 📝 Integration Summary

**Minimal changes required:**
1. Update root.html.heex with `h-full` classes
2. Add `dashboard/1` function to layouts.ex
3. Add `layout:` parameter to router live_session
4. Register Hooks in LiveSocket
5. Add `:current_path` and `:page_title` assigns to each LiveView

**Files to modify:**
- `lib/{app_name}_web/components/layouts/root.html.heex` (add h-full classes)
- `lib/{app_name}_web/components/layouts.ex` (add dashboard/1)
- `lib/{app_name}_web/router.ex` (add layout parameter)
- `lib/{app_name}_web/live/home_live.ex` (or your main LiveView - add assigns)
- `assets/js/app.js` (verify Hooks registration)

**Files to NOT create:**
- Do NOT create separate `dashboard_live.ex` if you want to wrap an existing LiveView
- Do NOT create setup/integration MD files in the project root (they're in the skill)

### 🎯 Success Criteria

Dashboard is successfully integrated when:
- [x] Server compiles without errors
- [x] Login redirects to dashboard layout
- [x] Sidebar shows navigation items
- [x] Hamburger menu toggles sidebar on mobile
- [x] Theme switcher works and persists
- [x] User dropdown shows correct user info
- [x] Logout works correctly
- [x] Current page is highlighted in navigation

---

**Generated by Dashboard Generator Skill**
This checklist is for LLM assistance during integration.
'''

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def find_project_root(start_path=None):
    """Find the Phoenix project root by looking for mix.exs"""
    current = Path(start_path or os.getcwd()).resolve()

    while current != current.parent:
        if (current / "mix.exs").exists():
            return current
        current = current.parent

    return None


def backup_file(file_path):
    """Create a backup of a file before modifying it"""
    if not file_path.exists():
        return None

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    # Create backup with format: filename.ext.timestamp.backup
    # This avoids .ex files being compiled by Elixir
    backup_path = file_path.with_name(f"{file_path.stem}{file_path.suffix}.{timestamp}.backup")

    import shutil
    shutil.copy2(file_path, backup_path)
    print(f"  Created backup: {backup_path}")
    return backup_path


def extract_project_info(project_root):
    """
    Extract project information from mix.exs

    Returns dict with:
        - base_module: Main module name (e.g., "FtvplusServer")
        - web_module: Web module name (e.g., "FtvplusServerWeb")
        - app_name: Application atom name (e.g., "ftvplus_server")
        - display_name: Human-readable name (e.g., "FtvplusServer")
    """
    import re

    mix_exs_path = project_root / "mix.exs"
    if not mix_exs_path.exists():
        raise FileNotFoundError(f"mix.exs not found at {mix_exs_path}")

    mix_exs = mix_exs_path.read_text()

    # Extract: defmodule MyApp.MixProject do
    module_match = re.search(r'defmodule\s+(\w+)\.MixProject', mix_exs)
    if not module_match:
        raise ValueError("Could not find 'defmodule X.MixProject' in mix.exs")
    base_module = module_match.group(1)

    # Extract: app: :my_app
    app_match = re.search(r'app:\s+:(\w+)', mix_exs)
    if not app_match:
        raise ValueError("Could not find 'app: :x' in mix.exs")
    app_name = app_match.group(1)

    # Derive display name from base_module (can be customized later)
    display_name = base_module

    return {
        'base_module': base_module,
        'web_module': f'{base_module}Web',
        'app_name': app_name,
        'display_name': display_name,
    }


def ensure_directory(path):
    """Ensure a directory exists"""
    path.mkdir(parents=True, exist_ok=True)


# ============================================================================
# GENERATION FUNCTIONS
# ============================================================================

def generate_dashboard_layout(project_root, project_info):
    """Generate the dashboard layout file"""
    app_name = project_info['app_name']
    layout_path = project_root / "lib" / f"{app_name}_web" / "components" / "layouts" / "dashboard.html.heex"

    # Check if exists
    if layout_path.exists():
        print(f"⚠️  Dashboard layout already exists: {layout_path}")
        response = input("  Overwrite? (y/N): ").strip().lower()
        if response != 'y':
            print("  Skipped.")
            return False
        backup_file(layout_path)

    # Ensure directory
    ensure_directory(layout_path.parent)

    # Write file with substitutions
    content = DASHBOARD_LAYOUT_TEMPLATE.format(**project_info)
    layout_path.write_text(content)
    print(f"✅ Created dashboard layout: {layout_path}")
    return True


def generate_dashboard_nav(project_root, project_info):
    """Generate the dashboard navigation components"""
    app_name = project_info['app_name']
    nav_path = project_root / "lib" / f"{app_name}_web" / "components" / "dashboard_nav.ex"

    # Check if exists
    if nav_path.exists():
        print(f"⚠️  Dashboard nav module already exists: {nav_path}")
        response = input("  Overwrite? (y/N): ").strip().lower()
        if response != 'y':
            print("  Skipped.")
            return False
        backup_file(nav_path)

    # Ensure directory
    ensure_directory(nav_path.parent)

    # Write file with substitutions
    content = DASHBOARD_NAV_TEMPLATE.format(**project_info)
    nav_path.write_text(content)
    print(f"✅ Created dashboard nav: {nav_path}")
    return True


def generate_dashboard_live(project_root, project_info):
    """Generate the dashboard LiveView (only if doesn't exist)"""
    app_name = project_info['app_name']
    live_path = project_root / "lib" / f"{app_name}_web" / "live" / "dashboard_live.ex"

    # Check if exists - DO NOT overwrite
    if live_path.exists():
        print(f"ℹ️  Dashboard LiveView already exists: {live_path}")
        print("  Skipping (existing file will not be modified).")
        return False

    # Ensure directory
    ensure_directory(live_path.parent)

    # Write file with substitutions
    content = DASHBOARD_LIVE_TEMPLATE.format(**project_info)
    live_path.write_text(content)
    print(f"✅ Created dashboard LiveView: {live_path}")
    return True


def update_router(project_root, project_info):
    """Update the router to use dashboard layout"""
    app_name = project_info['app_name']
    web_module = project_info['web_module']
    router_path = project_root / "lib" / f"{app_name}_web" / "router.ex"

    if not router_path.exists():
        print(f"❌ Router not found: {router_path}")
        return False

    # Read current router
    router_content = router_path.read_text()

    # Check if already has dashboard route
    if 'DashboardLive' in router_content:
        print(f"ℹ️  Router already configured for DashboardLive")
        return False

    # Backup
    backup_file(router_path)

    # Add instructions comment with project-specific module names
    instruction = f"""
  # Dashboard Layout Routes
  # Add your dashboard routes here using the :require_authenticated_user session
  # Example:
  #   live_session :require_authenticated_user,
  #     on_mount: [{{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}}],
  #     layout: {{{web_module}.Layouts, :dashboard}} do
  #     live "/", DashboardLive, :index
  #   end
"""

    # Find a good place to insert (after the first scope)
    scope_pattern = f'scope "/", {web_module} do'
    if scope_pattern in router_content:
        # Insert after the first scope definition
        parts = router_content.split(scope_pattern, 1)
        updated_content = parts[0] + scope_pattern + instruction + parts[1]

        router_path.write_text(updated_content)
        print(f"✅ Updated router with dashboard layout instructions: {router_path}")
        print("  ⚠️  Manual step required: Update your router to use :dashboard layout")
        return True

    print("⚠️  Could not automatically update router. Please add manually.")
    return False


def add_theme_hook(project_root):
    """Add theme toggle hook to app.js"""
    app_js_path = project_root / "assets" / "js" / "app.js"

    if not app_js_path.exists():
        print(f"⚠️  app.js not found: {app_js_path}")
        return False

    # Read current content
    content = app_js_path.read_text()

    # Check if hook already exists
    if 'ThemeToggle' in content:
        print(f"ℹ️  ThemeToggle hook already exists in app.js")
        return False

    # Backup
    backup_file(app_js_path)

    # Add hook at the end
    hook_code = f"""

// Theme Toggle Hook
{THEME_HOOK_JS}

// Add hook to LiveSocket
// If you have existing hooks, add ThemeToggle to them:
// let Hooks = {{ ...existingHooks, ThemeToggle }}
// Otherwise create new:
let Hooks = {{ ThemeToggle }};

// Update your LiveSocket initialization to include hooks:
// let liveSocket = new LiveSocket("/live", Socket, {{
//   ...params,
//   hooks: Hooks
// }})
"""

    content += hook_code
    app_js_path.write_text(content)

    print(f"✅ Added ThemeToggle hook to app.js")
    print("  ⚠️  Manual step required: Update LiveSocket initialization to use Hooks")
    return True


def generate_setup_instructions(project_root):
    """Generate the setup instructions markdown file"""
    instructions_path = project_root / "DASHBOARD_SETUP.md"

    instructions_path.write_text(SETUP_INSTRUCTIONS)
    print(f"✅ Created setup instructions: {instructions_path}")
    return True


def generate_integration_instructions(project_root, project_info):
    """Generate context-aware integration instructions for LLM"""
    instructions_path = project_root / "DASHBOARD_INTEGRATION.md"

    # Add timestamp
    project_info_with_timestamp = project_info.copy()
    project_info_with_timestamp['timestamp'] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Format template with project info
    content = INTEGRATION_INSTRUCTIONS.format(**project_info_with_timestamp)

    instructions_path.write_text(content)
    print(f"✅ Created integration guide: {instructions_path}")
    return True


def generate_llm_checklist(project_root, project_info):
    """Generate LLM-friendly integration checklist"""
    checklist_path = project_root / "DASHBOARD_LLM_CHECKLIST.md"

    # Add timestamp
    project_info_with_timestamp = project_info.copy()
    project_info_with_timestamp['timestamp'] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Format template with project info
    content = LLM_INTEGRATION_CHECKLIST.format(**project_info_with_timestamp)

    checklist_path.write_text(content)
    print(f"✅ Created LLM integration checklist: {checklist_path}")
    return True


# ============================================================================
# MAIN FUNCTION
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Dashboard layout structure for Phoenix LiveView with DaisyUI"
    )
    parser.add_argument(
        "--project-root",
        type=str,
        help="Path to Phoenix project root (auto-detected if not provided)"
    )

    args = parser.parse_args()

    # Find project root
    project_root = None
    if args.project_root:
        project_root = Path(args.project_root).resolve()
    else:
        project_root = find_project_root()

    if not project_root or not (project_root / "mix.exs").exists():
        print("❌ Error: Could not find Phoenix project root (mix.exs not found)")
        print("  Please run this script from your Phoenix project directory")
        print("  Or use: --project-root /path/to/project")
        sys.exit(1)

    # Extract project information
    try:
        project_info = extract_project_info(project_root)
    except Exception as e:
        print(f"❌ Error extracting project info: {e}")
        sys.exit(1)

    print(f"🚀 Generating Dashboard layout structure")
    print(f"  Project root: {project_root}")
    print(f"  Project: {project_info['display_name']}")
    print(f"  Module: {project_info['web_module']}")
    print(f"  App: {project_info['app_name']}")
    print()

    # Run generation steps
    steps = [
        ("Dashboard Layout", lambda: generate_dashboard_layout(project_root, project_info)),
        ("Dashboard Navigation", lambda: generate_dashboard_nav(project_root, project_info)),
        ("Dashboard LiveView", lambda: generate_dashboard_live(project_root, project_info)),
        ("Router Configuration", lambda: update_router(project_root, project_info)),
        ("Theme Toggle Hook", lambda: add_theme_hook(project_root)),
        ("Setup Instructions", lambda: generate_setup_instructions(project_root)),
        ("Integration Guide", lambda: generate_integration_instructions(project_root, project_info)),
        ("LLM Integration Checklist", lambda: generate_llm_checklist(project_root, project_info)),
    ]

    results = []
    for step_name, step_func in steps:
        print(f"\n{'='*60}")
        print(f"Step: {step_name}")
        print('='*60)
        try:
            result = step_func()
            results.append((step_name, result))
        except Exception as e:
            print(f"❌ Error in {step_name}: {e}")
            results.append((step_name, False))

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print('='*60)

    for step_name, result in results:
        status = "✅" if result else "⚠️ "
        print(f"{status} {step_name}")

    print(f"\n✨ Dashboard generation complete!")
    print(f"\n📖 Next steps:")
    print(f"  1. Review DASHBOARD_LLM_CHECKLIST.md for step-by-step integration")
    print(f"  2. Follow the checklist to complete all required configuration")
    print(f"  3. See DASHBOARD_SETUP.md for customization options")
    print(f"  4. Run 'mix phx.server' and visit http://localhost:4000")
    print()


if __name__ == "__main__":
    main()
