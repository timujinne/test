---
name: daisyui-tailwind-ui
description: This skill should be used when building web user interfaces with DaisyUI component library and Tailwind CSS. Use when creating Phoenix LiveView templates, HEEx files, HTML pages, or any frontend components that require styled UI elements, forms, navigation, data display, or responsive layouts using DaisyUI's pre-built components and Tailwind's utility classes.
---

# DaisyUI Tailwind UI

## Overview

This skill enables rapid development of modern, accessible, and responsive web interfaces using DaisyUI component library built on top of Tailwind CSS. DaisyUI provides semantic component classes that work seamlessly with Tailwind's utility-first approach, reducing the need to write custom CSS while maintaining design flexibility.

## When to Use This Skill

Use this skill when:
- Building Phoenix LiveView templates (`.heex` files) with styled components
- Creating HTML pages or frontend components requiring pre-styled UI elements
- Implementing forms, navigation menus, modals, cards, or data tables
- Needing responsive layouts with minimal custom CSS
- Wanting consistent design system without writing component CSS from scratch
- Converting design mockups into functional UI with DaisyUI components

## Core Principles

### 1. Utility-First with Semantic Components

DaisyUI combines Tailwind's utility classes with semantic component names:

```html
<!-- Pure Tailwind (verbose) -->
<button class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-700">
  Click me
</button>

<!-- DaisyUI (semantic) -->
<button class="btn btn-primary">Click me</button>

<!-- DaisyUI + Tailwind utilities (flexible) -->
<button class="btn btn-primary gap-2 w-full">
  <svg class="w-5 h-5">...</svg>
  Click me
</button>
```

### 2. Component Structure Pattern

Most DaisyUI components follow a consistent pattern:
- Base component class (e.g., `btn`, `card`, `modal`)
- Modifier classes for variants (e.g., `btn-primary`, `btn-lg`, `btn-outline`)
- Combine freely with Tailwind utilities (spacing, sizing, colors)

### 3. Phoenix LiveView Integration

When using with Phoenix LiveView, leverage Phoenix's component system:

```elixir
# In a LiveView component
def render(assigns) do
  ~H"""
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h2 class="card-title"><%= @title %></h2>
      <p><%= @description %></p>
      <div class="card-actions justify-end">
        <button class="btn btn-primary" phx-click="action">Action</button>
      </div>
    </div>
  </div>
  """
end
```

## Component Categories

### Actions
- **Buttons**: `btn`, `btn-primary`, `btn-secondary`, `btn-accent`, `btn-ghost`, `btn-link`
- **Dropdown**: `dropdown`, `dropdown-content`, `dropdown-hover`, `dropdown-end`
- **Modal**: `modal`, `modal-box`, `modal-action`, `modal-open`
- **Swap**: `swap`, `swap-active` (for toggle animations)

### Data Display
- **Card**: `card`, `card-body`, `card-title`, `card-actions`
- **Table**: `table`, `table-zebra`, `table-pin-rows`, `table-xs/sm/md/lg`
- **Badge**: `badge`, `badge-primary`, `badge-outline`, `badge-lg`
- **Avatar**: `avatar`, `avatar-group`, `placeholder`
- **Stats**: `stats`, `stat`, `stat-title`, `stat-value`, `stat-desc`

### Navigation
- **Navbar**: `navbar`, `navbar-start`, `navbar-center`, `navbar-end`
- **Menu**: `menu`, `menu-horizontal`, `menu-vertical`, `menu-compact`
- **Breadcrumbs**: `breadcrumbs`, `breadcrumb-item`
- **Tabs**: `tabs`, `tab`, `tab-active`, `tab-bordered`, `tab-lifted`
- **Drawer**: `drawer`, `drawer-toggle`, `drawer-side`, `drawer-content`

### Data Input
- **Input**: `input`, `input-bordered`, `input-primary`, `input-sm/md/lg`
- **Textarea**: `textarea`, `textarea-bordered`, `textarea-primary`
- **Select**: `select`, `select-bordered`, `select-primary`
- **Checkbox**: `checkbox`, `checkbox-primary`, `checkbox-sm/md/lg`
- **Radio**: `radio`, `radio-primary`
- **Toggle**: `toggle`, `toggle-primary`
- **Range**: `range`, `range-primary`
- **File Input**: `file-input`, `file-input-bordered`

### Layout
- **Divider**: `divider`, `divider-horizontal`, `divider-vertical`
- **Stack**: `stack` (for overlapping elements)
- **Join**: `join`, `join-item`, `join-vertical/horizontal`
- **Hero**: `hero`, `hero-content`, `hero-overlay`

### Feedback
- **Alert**: `alert`, `alert-info`, `alert-success`, `alert-warning`, `alert-error`
- **Progress**: `progress`, `progress-primary`
- **Radial Progress**: `radial-progress` with `--value` CSS variable
- **Toast**: Position alerts with Tailwind utilities
- **Loading**: `loading`, `loading-spinner`, `loading-dots`, `loading-ring`

## Building UI Components

### Step 1: Choose the Right Component

Start by identifying the UI pattern needed:
- **Form input?** → Use `input`, `select`, `checkbox`, etc.
- **Action trigger?** → Use `btn`, `dropdown`, or `modal`
- **Data display?** → Use `card`, `table`, `stats`, or `badge`
- **Navigation?** → Use `navbar`, `menu`, `tabs`, or `drawer`
- **User feedback?** → Use `alert`, `progress`, or `loading`

### Step 2: Apply Component Classes

```html
<!-- Example: Building a user profile card -->
<div class="card w-96 bg-base-100 shadow-xl">
  <figure><img src="/images/user.jpg" alt="User" /></figure>
  <div class="card-body">
    <h2 class="card-title">
      John Doe
      <div class="badge badge-secondary">PRO</div>
    </h2>
    <p>Full-stack developer passionate about Elixir and Phoenix</p>
    <div class="card-actions justify-end">
      <div class="badge badge-outline">Elixir</div>
      <div class="badge badge-outline">Phoenix</div>
    </div>
  </div>
</div>
```

### Step 3: Add Tailwind Utilities for Customization

Combine DaisyUI components with Tailwind utilities for precise control:

```html
<!-- Responsive grid of cards -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 p-4">
  <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
    <div class="card-body">
      <h2 class="card-title text-2xl font-bold">Feature 1</h2>
      <p class="text-base-content/70">Description goes here</p>
    </div>
  </div>
  <!-- More cards... -->
</div>
```

### Step 4: Add Interactivity (Phoenix LiveView)

For interactive components, use Phoenix LiveView bindings:

```elixir
~H"""
<div class="form-control w-full max-w-xs">
  <label class="label">
    <span class="label-text">Pick your favorite framework</span>
  </label>
  <select class="select select-bordered" phx-change="framework_changed">
    <option disabled selected>Choose one</option>
    <option value="phoenix">Phoenix</option>
    <option value="rails">Rails</option>
    <option value="django">Django</option>
  </select>
</div>

<!-- Modal with LiveView interaction -->
<input type="checkbox" id="my-modal" class="modal-toggle" />
<div class="modal">
  <div class="modal-box">
    <h3 class="font-bold text-lg">Confirmation</h3>
    <p class="py-4">Are you sure you want to proceed?</p>
    <div class="modal-action">
      <label for="my-modal" class="btn">Cancel</label>
      <button class="btn btn-primary" phx-click="confirm">Confirm</button>
    </div>
  </div>
</div>
"""
```

## Layout Patterns

### Container Pattern
```html
<div class="container mx-auto px-4">
  <!-- Content with responsive margins -->
</div>
```

### Navbar Pattern
```html
<div class="navbar bg-base-100 shadow-lg">
  <div class="navbar-start">
    <a class="btn btn-ghost text-xl">Brand</a>
  </div>
  <div class="navbar-center hidden lg:flex">
    <ul class="menu menu-horizontal px-1">
      <li><a>Home</a></li>
      <li><a>About</a></li>
      <li><a>Contact</a></li>
    </ul>
  </div>
  <div class="navbar-end">
    <button class="btn btn-primary">Get Started</button>
  </div>
</div>
```

### Hero Section Pattern
```html
<div class="hero min-h-screen bg-base-200">
  <div class="hero-content text-center">
    <div class="max-w-md">
      <h1 class="text-5xl font-bold">Hello there</h1>
      <p class="py-6">Provident cupiditate voluptatem et in...</p>
      <button class="btn btn-primary">Get Started</button>
    </div>
  </div>
</div>
```

### Sidebar Layout Pattern
```html
<div class="drawer lg:drawer-open">
  <input id="my-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content flex flex-col">
    <!-- Page content -->
    <label for="my-drawer" class="btn btn-primary drawer-button lg:hidden">
      Open drawer
    </label>
  </div>
  <div class="drawer-side">
    <label for="my-drawer" class="drawer-overlay"></label>
    <ul class="menu p-4 w-80 bg-base-100 text-base-content">
      <!-- Sidebar content -->
      <li><a>Item 1</a></li>
      <li><a>Item 2</a></li>
    </ul>
  </div>
</div>
```

### Form Layout Pattern
```html
<div class="card w-96 bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Sign Up</h2>
    <form>
      <div class="form-control">
        <label class="label">
          <span class="label-text">Email</span>
        </label>
        <input type="email" placeholder="email@example.com"
               class="input input-bordered" required />
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text">Password</span>
        </label>
        <input type="password" placeholder="password"
               class="input input-bordered" required />
      </div>
      <div class="form-control mt-6">
        <button class="btn btn-primary">Sign Up</button>
      </div>
    </form>
  </div>
</div>
```

## Responsive Design

### Mobile-First Approach

DaisyUI components are mobile-friendly by default. Use Tailwind's responsive prefixes for adjustments:

```html
<!-- Responsive grid -->
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
  <!-- Cards adapt to screen size -->
</div>

<!-- Responsive menu -->
<ul class="menu menu-vertical lg:menu-horizontal">
  <li><a>Item 1</a></li>
  <li><a>Item 2</a></li>
</ul>

<!-- Responsive button sizes -->
<button class="btn btn-sm md:btn-md lg:btn-lg">Responsive Button</button>
```

### Breakpoint Reference
- `sm:` - 640px and up
- `md:` - 768px and up
- `lg:` - 1024px and up
- `xl:` - 1280px and up
- `2xl:` - 1536px and up

## Theming and Customization

### Using Built-in Themes

DaisyUI includes 32+ themes. Apply them via `data-theme` attribute:

```html
<!-- Light theme -->
<html data-theme="light">

<!-- Dark theme -->
<html data-theme="dark">

<!-- Other themes: cupcake, bumblebee, emerald, corporate, synthwave, retro, cyberpunk, valentine, halloween, garden, forest, aqua, lofi, pastel, fantasy, wireframe, black, luxury, dracula, cmyk, autumn, business, acid, lemonade, night, coffee, winter, dim, nord, sunset -->
```

For theme switching in Phoenix LiveView:

```elixir
# In app.html.heex or root.html.heex
<html lang="en" data-theme={@theme || "light"}>
```

### Color System

DaisyUI uses semantic color names:
- `primary` - Main brand color
- `secondary` - Secondary brand color
- `accent` - Accent color for highlights
- `neutral` - Neutral color for text and borders
- `base-100`, `base-200`, `base-300` - Background colors
- `info`, `success`, `warning`, `error` - Feedback colors

```html
<!-- Using semantic colors -->
<button class="btn btn-primary">Primary</button>
<button class="btn btn-secondary">Secondary</button>
<button class="btn btn-accent">Accent</button>
<div class="alert alert-success">Success message</div>
<div class="alert alert-error">Error message</div>
```

### Customizing Theme Colors

Customize themes in `tailwind.config.js`:

```javascript
module.exports = {
  daisyui: {
    themes: [
      {
        mytheme: {
          "primary": "#570df8",
          "secondary": "#f000b8",
          "accent": "#37cdbe",
          "neutral": "#3d4451",
          "base-100": "#ffffff",
          "info": "#3abff8",
          "success": "#36d399",
          "warning": "#fbbd23",
          "error": "#f87272",
        },
      },
    ],
  },
}
```

## Best Practices

### 1. Component Reusability

Create Phoenix function components for reusable UI patterns:

```elixir
# In a component module
def card(assigns) do
  ~H"""
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h2 class="card-title"><%= @title %></h2>
      <p><%= @description %></p>
      <%= render_slot(@inner_block) %>
    </div>
  </div>
  """
end

# Usage
<.card title="My Card" description="Card description">
  <div class="card-actions justify-end">
    <button class="btn btn-primary">Action</button>
  </div>
</.card>
```

### 2. Accessibility

DaisyUI components include accessibility features, but always:
- Add proper `aria-label` attributes to icon-only buttons
- Use semantic HTML elements
- Ensure keyboard navigation works
- Test with screen readers

```html
<!-- Good accessibility -->
<button class="btn btn-circle" aria-label="Close menu">
  <svg class="w-6 h-6">...</svg>
</button>

<label class="label">
  <span class="label-text">Email address</span>
</label>
<input type="email" class="input input-bordered"
       aria-describedby="email-help" />
<span id="email-help" class="label-text-alt">We'll never share your email</span>
```

### 3. Performance

- Use `hidden` class instead of JavaScript for conditional rendering when possible
- Leverage Phoenix LiveView's efficient diff algorithm
- Load only needed Tailwind utilities (configure `purge` in `tailwind.config.js`)

### 4. Consistency

- Establish a component library for your project
- Use consistent spacing scale (Tailwind's built-in scale)
- Stick to one or two themes throughout the application
- Create design tokens for custom colors and spacing

### 5. Progressive Enhancement

Start with semantic HTML, then enhance with DaisyUI:

```html
<!-- Works without CSS -->
<form>
  <label>Email: <input type="email" name="email" /></label>
  <button type="submit">Submit</button>
</form>

<!-- Enhanced with DaisyUI -->
<form>
  <div class="form-control">
    <label class="label">
      <span class="label-text">Email</span>
    </label>
    <input type="email" name="email" class="input input-bordered" />
  </div>
  <button type="submit" class="btn btn-primary">Submit</button>
</form>
```

## Common Patterns

### Loading States
```html
<!-- Button loading -->
<button class="btn btn-primary loading">Processing...</button>

<!-- Spinner -->
<span class="loading loading-spinner loading-lg"></span>

<!-- Skeleton loading -->
<div class="flex flex-col gap-4 w-52">
  <div class="skeleton h-32 w-full"></div>
  <div class="skeleton h-4 w-28"></div>
  <div class="skeleton h-4 w-full"></div>
</div>
```

### Empty States
```html
<div class="hero min-h-screen bg-base-200">
  <div class="hero-content text-center">
    <div class="max-w-md">
      <h1 class="text-5xl font-bold">No items found</h1>
      <p class="py-6">Start by creating your first item.</p>
      <button class="btn btn-primary">Create Item</button>
    </div>
  </div>
</div>
```

### Confirmation Dialogs
```elixir
~H"""
<input type="checkbox" id="confirm-modal" class="modal-toggle" />
<div class="modal">
  <div class="modal-box">
    <h3 class="font-bold text-lg">Delete Item</h3>
    <p class="py-4">This action cannot be undone. Continue?</p>
    <div class="modal-action">
      <label for="confirm-modal" class="btn">Cancel</label>
      <button class="btn btn-error" phx-click="delete" phx-value-id={@item_id}>
        Delete
      </button>
    </div>
  </div>
</div>
"""
```

### Notification Toast
```html
<div class="toast toast-top toast-end">
  <div class="alert alert-success">
    <span>Message sent successfully!</span>
  </div>
</div>
```

## Dashboard Generator Script

This skill includes a Python script that generates a complete Dashboard layout structure for Phoenix LiveView applications with PhoenixKit authentication integration.

### What It Generates

The `generate_dashboard.py` script creates:

1. **Dashboard Layout** (`lib/..._web/components/layouts/dashboard.html.heex`)
   - DaisyUI drawer-based layout with sidebar navigation
   - Toggle button that opens/closes sidebar on all screen sizes
   - Sidebar open by default on desktop (`lg:drawer-open`)
   - Header with project title, theme switcher, and user dropdown
   - Responsive mobile drawer with overlay

2. **Navigation Components** (`lib/..._web/components/dashboard_nav.ex`)
   - `nav_item/1` - Navigation menu items with icons and active states
   - `user_dropdown/1` - User profile dropdown with email and logout
   - `theme_switcher/1` - Light/Dark theme toggle
   - Icon helpers for common navigation icons

3. **Dashboard LiveView** (`lib/..._web/live/dashboard_live.ex`)
   - **Only created if file doesn't exist** - preserves existing dashboard
   - Placeholder dashboard with welcome message and stat cards
   - Ready to customize with your application's data

4. **Router Updates** (`lib/..._web/router.ex`)
   - Instructions for integrating dashboard layout
   - Safe updates that don't break existing routes

5. **Theme Toggle Hook** (`assets/js/app.js`)
   - JavaScript hook for theme persistence
   - Saves theme preference to localStorage
   - Minimal JavaScript footprint

6. **Setup Instructions** (`DASHBOARD_SETUP.md`)
   - Complete customization guide for LLM or developers
   - Examples for adding menu items, icons, widgets
   - Troubleshooting common issues

### Usage

From your Phoenix project root:

```bash
python3 .claude/daisyui-tailwind-ui/scripts/generate_dashboard.py
```

Or specify project path:

```bash
python3 .claude/daisyui-tailwind-ui/scripts/generate_dashboard.py --project-root /path/to/project
```

### Features

- **Non-destructive**: Won't overwrite existing DashboardLive
- **Safe backups**: Creates timestamped backups before modifying files
- **Interactive**: Prompts before overwriting existing layouts
- **PhoenixKit integrated**: Uses `@phoenix_kit_current_scope` for auth
- **Minimal JavaScript**: Relies on DaisyUI CSS classes
- **Responsive**: Mobile-first design with drawer pattern

### Menu Structure

Default menu includes:
- Dashboard (home icon)
- Easy to extend with more items

Example menu items you can add:
- Films (film icon)
- Translations (translation icon)
- Live Streams (stream icon)
- Settings (settings icon)

### Customization

After generation, customize via `DASHBOARD_SETUP.md`:
- Add new menu items
- Create nested submenus
- Add custom icons
- Implement widgets and stat cards
- Change project title and branding
- Configure additional themes

### Integration Requirements

The script assumes your project has:
- Phoenix 1.7+ with LiveView
- PhoenixKit for authentication
- DaisyUI configured in Tailwind
- Standard Phoenix project structure

All requirements are met if you're using PhoenixKit with DaisyUI.

### Post-Generation Steps

1. Review `DASHBOARD_SETUP.md` for customization options
2. Update `router.ex` to use `:dashboard` layout (see comments in file)
3. Add `Hooks` to LiveSocket in `assets/js/app.js`
4. Run `mix phx.server` and test the dashboard
5. Customize menu items and dashboard content

## Resources

### Reference Documentation

For detailed component specifications and advanced usage, see:
- `references/components_reference.md` - Comprehensive DaisyUI component documentation
- `references/tailwind_utilities.md` - Essential Tailwind utility classes
- `references/phoenix_integration.md` - Phoenix LiveView integration patterns

### Component Templates

Ready-to-use component templates are available in:
- `assets/page_templates/` - Complete page layouts (dashboard, landing, auth)
- `assets/component_snippets/` - Reusable component code snippets

### Quick Reference

**Most Used Components:**
1. `btn` + modifiers - Buttons and action triggers
2. `card` + `card-body` - Content containers
3. `input` + `form-control` - Form inputs
4. `navbar` + `menu` - Navigation
5. `modal` + `modal-box` - Dialogs and overlays
6. `alert` - User feedback messages
7. `table` - Data tables
8. `drawer` - Sidebar layouts
9. `badge` - Labels and tags
10. `loading` - Loading indicators

**Essential Tailwind Utilities:**
- Layout: `flex`, `grid`, `container`
- Spacing: `p-4`, `m-4`, `gap-4`, `space-x-4`
- Sizing: `w-full`, `h-screen`, `max-w-md`
- Typography: `text-lg`, `font-bold`, `text-center`
- Colors: `bg-base-100`, `text-primary`
- Responsive: `sm:`, `md:`, `lg:`, `xl:`
