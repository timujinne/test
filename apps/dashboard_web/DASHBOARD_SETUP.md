# Dashboard Setup Instructions

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
