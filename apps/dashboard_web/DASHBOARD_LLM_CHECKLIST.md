# Dashboard Integration Checklist for LLM

**Generated:** 2025-11-25 15:58:15
**Project:** DashboardWeb
**Module:** DashboardWebWeb

## Quick Integration Checklist

Use this checklist when integrating the generated dashboard into a Phoenix LiveView project.

### ✅ Step 1: Verify Generated Files

Check that these files were created successfully:

- [ ] `lib/dashboard_web_web/components/layouts/dashboard.html.heex` - Dashboard partial layout (NO <html>, <head>, <body> tags)
- [ ] `lib/dashboard_web_web/components/dashboard_nav.ex` - Navigation components
- [ ] `assets/js/app.js` - Contains ThemeToggle hook

**IMPORTANT:** Dashboard layout is a **partial layout**, not a full HTML document. The root.html.heex provides the HTML wrapper.

### ✅ Step 2: Update Root Layout

**File:** `lib/dashboard_web_web/components/layouts/root.html.heex`

Add required classes for dashboard to work properly:

```heex
<!DOCTYPE html>
<html lang="en" class="h-full [scrollbar-gutter:stable]">  <!-- ← ADD h-full -->
  <head>
    <!-- ... head content ... -->
  </head>
  <body class="h-full bg-base-200">  <!-- ← ADD h-full and bg-base-200 -->
    {@inner_content}
  </body>
</html>
```

**Why:** Dashboard uses `h-screen` which requires parent elements to have `h-full` for proper height.

### ✅ Step 3: Configure layouts.ex

The layouts module MUST have a `dashboard/1` function that wraps the generated template.

**File:** `lib/dashboard_web_web/components/layouts.ex`

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

**File:** `lib/dashboard_web_web/router.ex`

**Find the authenticated live_session:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}] do

  live "/", HomeLive, :home
end
```

**Add layout parameter:**
```elixir
live_session :require_authenticated_user,
  on_mount: [{PhoenixKitWeb.Users.Auth, :phoenix_kit_ensure_authenticated_scope}],
  layout: {DashboardWebWeb.Layouts, :dashboard} do  # ← ADD THIS

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
export const ThemeToggle = {
  mounted() {
    const savedTheme = localStorage.getItem('theme') || 'light';
    this.setTheme(savedTheme);
    if (savedTheme === 'dark') { this.el.checked = true; }
    this.el.addEventListener('change', (e) => {
      this.setTheme(e.target.checked ? 'dark' : 'light');
    });
  },
  setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }
};

// Create Hooks object
let Hooks = { ThemeToggle };

// Initialize LiveSocket with hooks
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks  // ← MUST BE HERE
});

// Connect AFTER LiveSocket is defined
liveSocket.connect();

// Expose on window
window.liveSocket = liveSocket;
```

**If you have existing hooks:**
```javascript
let Hooks = { ThemeToggle, ...existingHooks };
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

  {:ok, socket}
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
<meta name="csrf-token" content={get_csrf_token()} />

<!-- Wrong: -->
<meta name="csrf-token" content={@csrf_token} />
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
import {web_module}.CoreComponents
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
<link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
<script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
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
- Root layout's `{@inner_content}` renders dashboard content

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
- `lib/dashboard_web_web/components/layouts/root.html.heex` (add h-full classes)
- `lib/dashboard_web_web/components/layouts.ex` (add dashboard/1)
- `lib/dashboard_web_web/router.ex` (add layout parameter)
- `lib/dashboard_web_web/live/home_live.ex` (or your main LiveView - add assigns)
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
