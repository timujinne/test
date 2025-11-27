# DaisyUI Components Reference

Complete reference for all DaisyUI components with usage examples and variants.

## Actions

### Button (`btn`)

**Base classes:** `btn`

**Modifiers:**
- **Colors**: `btn-primary`, `btn-secondary`, `btn-accent`, `btn-neutral`, `btn-ghost`, `btn-link`
- **States**: `btn-info`, `btn-success`, `btn-warning`, `btn-error`
- **Sizes**: `btn-xs`, `btn-sm`, `btn-md`, `btn-lg`
- **Styles**: `btn-outline`, `btn-active`, `btn-disabled`
- **Shapes**: `btn-circle`, `btn-square`, `btn-wide`, `btn-block`
- **States**: `loading`, `disabled`

**Examples:**

```html
<!-- Basic buttons -->
<button class="btn">Default</button>
<button class="btn btn-primary">Primary</button>
<button class="btn btn-secondary">Secondary</button>
<button class="btn btn-accent">Accent</button>

<!-- Outlined buttons -->
<button class="btn btn-outline">Default</button>
<button class="btn btn-outline btn-primary">Primary</button>

<!-- Sizes -->
<button class="btn btn-xs">Tiny</button>
<button class="btn btn-sm">Small</button>
<button class="btn btn-md">Normal</button>
<button class="btn btn-lg">Large</button>

<!-- Special shapes -->
<button class="btn btn-circle">
  <svg class="w-6 h-6">...</svg>
</button>
<button class="btn btn-square">SQ</button>
<button class="btn btn-wide">Wide button</button>
<button class="btn btn-block">Full width</button>

<!-- Loading state -->
<button class="btn loading">Loading</button>
<button class="btn loading btn-primary">Saving...</button>

<!-- With icon -->
<button class="btn gap-2">
  <svg class="w-5 h-5">...</svg>
  Button with icon
</button>
```

### Dropdown (`dropdown`)

**Base classes:** `dropdown`

**Modifiers:**
- **Alignment**: `dropdown-end`, `dropdown-top`, `dropdown-bottom`, `dropdown-left`, `dropdown-right`
- **Behavior**: `dropdown-hover`, `dropdown-open`

**Structure:**
- `dropdown` - Container
- `dropdown-content` - Content container (usually with menu inside)

**Examples:**

```html
<!-- Basic dropdown -->
<div class="dropdown">
  <label tabindex="0" class="btn m-1">Click</label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
    <li><a>Item 1</a></li>
    <li><a>Item 2</a></li>
  </ul>
</div>

<!-- Dropdown on hover -->
<div class="dropdown dropdown-hover">
  <label tabindex="0" class="btn m-1">Hover</label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
    <li><a>Item 1</a></li>
    <li><a>Item 2</a></li>
  </ul>
</div>

<!-- Dropdown alignment -->
<div class="dropdown dropdown-end">
  <label tabindex="0" class="btn m-1">Click</label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
    <li><a>Item 1</a></li>
    <li><a>Item 2</a></li>
  </ul>
</div>

<!-- Dropdown with Phoenix LiveView -->
<div class="dropdown">
  <label tabindex="0" class="btn">Actions</label>
  <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
    <li><a phx-click="edit">Edit</a></li>
    <li><a phx-click="delete">Delete</a></li>
  </ul>
</div>
```

### Modal (`modal`)

**Base classes:** `modal`

**Modifiers:**
- **Position**: `modal-top`, `modal-middle`, `modal-bottom`
- **State**: `modal-open`

**Structure:**
- `modal` - Container
- `modal-box` - Content container
- `modal-action` - Action buttons container

**Examples:**

```html
<!-- Modal with checkbox toggle -->
<input type="checkbox" id="my-modal" class="modal-toggle" />
<div class="modal">
  <div class="modal-box">
    <h3 class="font-bold text-lg">Title</h3>
    <p class="py-4">Modal content goes here</p>
    <div class="modal-action">
      <label for="my-modal" class="btn">Close</label>
    </div>
  </div>
</div>

<!-- Trigger button -->
<label for="my-modal" class="btn">Open Modal</label>

<!-- Modal with backdrop close -->
<input type="checkbox" id="my-modal-2" class="modal-toggle" />
<label for="my-modal-2" class="modal cursor-pointer">
  <label class="modal-box relative" for="">
    <h3 class="text-lg font-bold">Title</h3>
    <p class="py-4">Click outside to close</p>
  </label>
</label>

<!-- Modal with Phoenix LiveView -->
<div class={"modal", "modal-open": @show_modal}>
  <div class="modal-box">
    <h3 class="font-bold text-lg"><%= @modal_title %></h3>
    <p class="py-4"><%= @modal_content %></p>
    <div class="modal-action">
      <button class="btn" phx-click="close_modal">Cancel</button>
      <button class="btn btn-primary" phx-click="confirm">Confirm</button>
    </div>
  </div>
</div>
```

### Swap (`swap`)

**Base classes:** `swap`

**Modifiers:**
- **Animation**: `swap-rotate`, `swap-flip`
- **State**: `swap-active`

**Examples:**

```html
<!-- Swap with rotate -->
<label class="swap swap-rotate">
  <input type="checkbox" />
  <div class="swap-on">ON</div>
  <div class="swap-off">OFF</div>
</label>

<!-- Theme toggle example -->
<label class="swap swap-rotate">
  <input type="checkbox" />
  <svg class="swap-on fill-current w-10 h-10" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
    <path d="M5.64,17l-.71.71a1,1,0,0,0,0,1.41,1,1,0,0,0,1.41,0l.71-.71A1,1,0,0,0,5.64,17ZM5,12a1,1,0,0,0-1-1H3a1,1,0,0,0,0,2H4A1,1,0,0,0,5,12Zm7-7a1,1,0,0,0,1-1V3a1,1,0,0,0-2,0V4A1,1,0,0,0,12,5ZM5.64,7.05a1,1,0,0,0,.7.29,1,1,0,0,0,.71-.29,1,1,0,0,0,0-1.41l-.71-.71A1,1,0,0,0,4.93,6.34Zm12,.29a1,1,0,0,0,.7-.29l.71-.71a1,1,0,1,0-1.41-1.41L17,5.64a1,1,0,0,0,0,1.41A1,1,0,0,0,17.66,7.34ZM21,11H20a1,1,0,0,0,0,2h1a1,1,0,0,0,0-2Zm-9,8a1,1,0,0,0-1,1v1a1,1,0,0,0,2,0V20A1,1,0,0,0,12,19ZM18.36,17A1,1,0,0,0,17,18.36l.71.71a1,1,0,0,0,1.41,0,1,1,0,0,0,0-1.41ZM12,6.5A5.5,5.5,0,1,0,17.5,12,5.51,5.51,0,0,0,12,6.5Zm0,9A3.5,3.5,0,1,1,15.5,12,3.5,3.5,0,0,1,12,15.5Z"/>
  </svg>
  <svg class="swap-off fill-current w-10 h-10" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
    <path d="M21.64,13a1,1,0,0,0-1.05-.14,8.05,8.05,0,0,1-3.37.73A8.15,8.15,0,0,1,9.08,5.49a8.59,8.59,0,0,1,.25-2A1,1,0,0,0,8,2.36,10.14,10.14,0,1,0,22,14.05,1,1,0,0,0,21.64,13Zm-9.5,6.69A8.14,8.14,0,0,1,7.08,5.22v.27A10.15,10.15,0,0,0,17.22,15.63a9.79,9.79,0,0,0,2.1-.22A8.11,8.11,0,0,1,12.14,19.73Z"/>
  </svg>
</label>
```

## Data Display

### Card (`card`)

**Base classes:** `card`

**Modifiers:**
- **Styles**: `card-bordered`, `card-compact`, `card-normal`, `card-side`
- **Background**: `card-body` (child element)

**Structure:**
- `card` - Container
- `figure` - Image container (optional)
- `card-body` - Content container
- `card-title` - Title element
- `card-actions` - Actions container

**Examples:**

```html
<!-- Basic card -->
<div class="card w-96 bg-base-100 shadow-xl">
  <figure><img src="/images/stock/photo.jpg" alt="Shoes" /></figure>
  <div class="card-body">
    <h2 class="card-title">Card title!</h2>
    <p>Description of the card content</p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary">Buy Now</button>
    </div>
  </div>
</div>

<!-- Compact card -->
<div class="card card-compact w-96 bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Compact card</h2>
    <p>Less padding, more compact look</p>
  </div>
</div>

<!-- Card with badge -->
<div class="card w-96 bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">
      Card title
      <div class="badge badge-secondary">NEW</div>
    </h2>
    <p>Card with badge in title</p>
  </div>
</div>

<!-- Side card (horizontal layout) -->
<div class="card card-side bg-base-100 shadow-xl">
  <figure><img src="/images/stock/photo.jpg" alt="Movie"/></figure>
  <div class="card-body">
    <h2 class="card-title">New movie is released!</h2>
    <p>Click the button to watch on Jetflix app.</p>
    <div class="card-actions justify-end">
      <button class="btn btn-primary">Watch</button>
    </div>
  </div>
</div>
```

### Table (`table`)

**Base classes:** `table`

**Modifiers:**
- **Styles**: `table-zebra`, `table-pin-rows`, `table-pin-cols`
- **Sizes**: `table-xs`, `table-sm`, `table-md`, `table-lg`

**Examples:**

```html
<!-- Basic table -->
<div class="overflow-x-auto">
  <table class="table">
    <thead>
      <tr>
        <th></th>
        <th>Name</th>
        <th>Job</th>
        <th>Favorite Color</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <th>1</th>
        <td>Cy Ganderton</td>
        <td>Quality Control Specialist</td>
        <td>Blue</td>
      </tr>
    </tbody>
  </table>
</div>

<!-- Zebra striped table -->
<table class="table table-zebra">
  <thead>
    <tr>
      <th>Name</th>
      <th>Email</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>John Doe</td>
      <td>john@example.com</td>
    </tr>
    <tr>
      <td>Jane Smith</td>
      <td>jane@example.com</td>
    </tr>
  </tbody>
</table>

<!-- Compact table -->
<table class="table table-xs">
  <thead>
    <tr>
      <th>ID</th>
      <th>Name</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td>
      <td>Compact row</td>
    </tr>
  </tbody>
</table>

<!-- Table with Phoenix LiveView -->
<table class="table table-zebra">
  <thead>
    <tr>
      <th>Name</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <%= for item <- @items do %>
      <tr>
        <td><%= item.name %></td>
        <td>
          <button class="btn btn-sm btn-ghost" phx-click="edit" phx-value-id={item.id}>
            Edit
          </button>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>
```

### Badge (`badge`)

**Base classes:** `badge`

**Modifiers:**
- **Colors**: `badge-primary`, `badge-secondary`, `badge-accent`, `badge-ghost`
- **States**: `badge-info`, `badge-success`, `badge-warning`, `badge-error`
- **Styles**: `badge-outline`
- **Sizes**: `badge-xs`, `badge-sm`, `badge-md`, `badge-lg`

**Examples:**

```html
<!-- Basic badges -->
<div class="badge">Default</div>
<div class="badge badge-primary">Primary</div>
<div class="badge badge-secondary">Secondary</div>
<div class="badge badge-accent">Accent</div>

<!-- Outlined badges -->
<div class="badge badge-outline">Default</div>
<div class="badge badge-outline badge-primary">Primary</div>

<!-- State badges -->
<div class="badge badge-info">Info</div>
<div class="badge badge-success">Success</div>
<div class="badge badge-warning">Warning</div>
<div class="badge badge-error">Error</div>

<!-- Size variants -->
<div class="badge badge-xs">XS</div>
<div class="badge badge-sm">SM</div>
<div class="badge badge-md">MD</div>
<div class="badge badge-lg">LG</div>

<!-- Badge in button -->
<button class="btn gap-2">
  Inbox
  <div class="badge">99+</div>
</button>
```

### Avatar (`avatar`)

**Base classes:** `avatar`

**Modifiers:**
- **Styles**: `avatar-group`, `placeholder`, `online`, `offline`

**Examples:**

```html
<!-- Single avatar -->
<div class="avatar">
  <div class="w-24 rounded-full">
    <img src="/images/avatar.jpg" />
  </div>
</div>

<!-- Avatar with online indicator -->
<div class="avatar online">
  <div class="w-24 rounded-full">
    <img src="/images/avatar.jpg" />
  </div>
</div>

<!-- Avatar placeholder -->
<div class="avatar placeholder">
  <div class="bg-neutral text-neutral-content rounded-full w-24">
    <span class="text-3xl">JD</span>
  </div>
</div>

<!-- Avatar group -->
<div class="avatar-group -space-x-6">
  <div class="avatar">
    <div class="w-12">
      <img src="/images/avatar1.jpg" />
    </div>
  </div>
  <div class="avatar">
    <div class="w-12">
      <img src="/images/avatar2.jpg" />
    </div>
  </div>
  <div class="avatar placeholder">
    <div class="w-12 bg-neutral text-neutral-content">
      <span>+99</span>
    </div>
  </div>
</div>
```

### Stats (`stats`)

**Base classes:** `stats`

**Modifiers:**
- **Layout**: `stats-horizontal`, `stats-vertical`

**Structure:**
- `stats` - Container
- `stat` - Individual stat
- `stat-figure` - Icon/figure area
- `stat-title` - Title
- `stat-value` - Main value
- `stat-desc` - Description

**Examples:**

```html
<!-- Basic stats -->
<div class="stats shadow">
  <div class="stat">
    <div class="stat-title">Total Page Views</div>
    <div class="stat-value">89,400</div>
    <div class="stat-desc">21% more than last month</div>
  </div>
</div>

<!-- Multiple stats -->
<div class="stats shadow">
  <div class="stat">
    <div class="stat-figure text-primary">
      <svg class="w-8 h-8">...</svg>
    </div>
    <div class="stat-title">Downloads</div>
    <div class="stat-value text-primary">31K</div>
    <div class="stat-desc">Jan 1st - Feb 1st</div>
  </div>

  <div class="stat">
    <div class="stat-figure text-secondary">
      <svg class="w-8 h-8">...</svg>
    </div>
    <div class="stat-title">New Users</div>
    <div class="stat-value text-secondary">4,200</div>
    <div class="stat-desc">↗︎ 400 (22%)</div>
  </div>

  <div class="stat">
    <div class="stat-figure text-accent">
      <svg class="w-8 h-8">...</svg>
    </div>
    <div class="stat-title">New Registers</div>
    <div class="stat-value">1,200</div>
    <div class="stat-desc">↘︎ 90 (14%)</div>
  </div>
</div>

<!-- Vertical stats -->
<div class="stats stats-vertical shadow">
  <div class="stat">
    <div class="stat-title">Downloads</div>
    <div class="stat-value">31K</div>
  </div>
  <div class="stat">
    <div class="stat-title">New Users</div>
    <div class="stat-value">4,200</div>
  </div>
</div>
```

## Navigation

### Navbar (`navbar`)

**Base classes:** `navbar`

**Structure:**
- `navbar` - Container
- `navbar-start` - Left section
- `navbar-center` - Center section
- `navbar-end` - Right section

**Examples:**

```html
<!-- Basic navbar -->
<div class="navbar bg-base-100">
  <div class="navbar-start">
    <a class="btn btn-ghost text-xl">daisyUI</a>
  </div>
  <div class="navbar-center hidden lg:flex">
    <ul class="menu menu-horizontal px-1">
      <li><a>Item 1</a></li>
      <li><a>Item 2</a></li>
      <li><a>Item 3</a></li>
    </ul>
  </div>
  <div class="navbar-end">
    <button class="btn">Button</button>
  </div>
</div>

<!-- Navbar with dropdown menu (mobile) -->
<div class="navbar bg-base-100">
  <div class="navbar-start">
    <div class="dropdown">
      <label tabindex="0" class="btn btn-ghost lg:hidden">
        <svg class="w-5 h-5"><!-- hamburger icon --></svg>
      </label>
      <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
        <li><a>Item 1</a></li>
        <li><a>Item 2</a></li>
        <li><a>Item 3</a></li>
      </ul>
    </div>
    <a class="btn btn-ghost text-xl">Brand</a>
  </div>
  <div class="navbar-center hidden lg:flex">
    <ul class="menu menu-horizontal px-1">
      <li><a>Item 1</a></li>
      <li><a>Item 2</a></li>
    </ul>
  </div>
  <div class="navbar-end">
    <button class="btn">Get started</button>
  </div>
</div>
```

### Menu (`menu`)

**Base classes:** `menu`

**Modifiers:**
- **Layout**: `menu-horizontal`, `menu-vertical`
- **Sizes**: `menu-xs`, `menu-sm`, `menu-md`, `menu-lg`
- **Styles**: `menu-compact`

**Examples:**

```html
<!-- Vertical menu -->
<ul class="menu bg-base-100 w-56 rounded-box">
  <li><a>Item 1</a></li>
  <li><a>Item 2</a></li>
  <li><a>Item 3</a></li>
</ul>

<!-- Horizontal menu -->
<ul class="menu menu-horizontal bg-base-100 rounded-box">
  <li><a>Item 1</a></li>
  <li><a>Item 2</a></li>
  <li><a>Item 3</a></li>
</ul>

<!-- Menu with submenu -->
<ul class="menu bg-base-100 w-56 rounded-box">
  <li><a>Item 1</a></li>
  <li>
    <details>
      <summary>Parent</summary>
      <ul>
        <li><a>Submenu 1</a></li>
        <li><a>Submenu 2</a></li>
      </ul>
    </details>
  </li>
  <li><a>Item 3</a></li>
</ul>

<!-- Menu with active item -->
<ul class="menu bg-base-100 w-56 rounded-box">
  <li><a>Item 1</a></li>
  <li><a class="active">Item 2</a></li>
  <li><a>Item 3</a></li>
</ul>
```

### Breadcrumbs (`breadcrumbs`)

**Base classes:** `breadcrumbs`

**Examples:**

```html
<!-- Basic breadcrumbs -->
<div class="text-sm breadcrumbs">
  <ul>
    <li><a>Home</a></li>
    <li><a>Documents</a></li>
    <li>Add Document</li>
  </ul>
</div>

<!-- Breadcrumbs with icons -->
<div class="text-sm breadcrumbs">
  <ul>
    <li>
      <a>
        <svg class="w-4 h-4 mr-2">...</svg>
        Home
      </a>
    </li>
    <li>
      <a>
        <svg class="w-4 h-4 mr-2">...</svg>
        Documents
      </a>
    </li>
    <li>
      <svg class="w-4 h-4 mr-2">...</svg>
      Add Document
    </li>
  </ul>
</div>
```

### Tabs (`tabs`)

**Base classes:** `tabs`

**Modifiers:**
- **Styles**: `tabs-boxed`, `tabs-bordered`, `tabs-lifted`
- **Sizes**: `tabs-xs`, `tabs-sm`, `tabs-md`, `tabs-lg`

**Structure:**
- `tabs` - Container
- `tab` - Individual tab
- `tab-active` - Active tab state

**Examples:**

```html
<!-- Basic tabs -->
<div class="tabs">
  <a class="tab">Tab 1</a>
  <a class="tab tab-active">Tab 2</a>
  <a class="tab">Tab 3</a>
</div>

<!-- Bordered tabs -->
<div class="tabs tabs-bordered">
  <a class="tab">Tab 1</a>
  <a class="tab tab-active">Tab 2</a>
  <a class="tab">Tab 3</a>
</div>

<!-- Lifted tabs -->
<div class="tabs tabs-lifted">
  <a class="tab">Tab 1</a>
  <a class="tab tab-active">Tab 2</a>
  <a class="tab">Tab 3</a>
</div>

<!-- Boxed tabs -->
<div class="tabs tabs-boxed">
  <a class="tab">Tab 1</a>
  <a class="tab tab-active">Tab 2</a>
  <a class="tab">Tab 3</a>
</div>
```

## Data Input

### Form Control (`form-control`)

**Base classes:** `form-control`

**Structure:**
- `form-control` - Container
- `label` - Label container
- `label-text` - Label text
- `label-text-alt` - Alternative/helper text

**Examples:**

```html
<!-- Form control with input -->
<div class="form-control w-full max-w-xs">
  <label class="label">
    <span class="label-text">What is your name?</span>
  </label>
  <input type="text" placeholder="Type here" class="input input-bordered w-full max-w-xs" />
  <label class="label">
    <span class="label-text-alt">Alt label</span>
  </label>
</div>

<!-- Form control with validation message -->
<div class="form-control">
  <label class="label">
    <span class="label-text">Email</span>
  </label>
  <input type="email" class="input input-bordered input-error" />
  <label class="label">
    <span class="label-text-alt text-error">Email is invalid</span>
  </label>
</div>
```

### Input (`input`)

**Base classes:** `input`

**Modifiers:**
- **Colors**: `input-primary`, `input-secondary`, `input-accent`
- **States**: `input-info`, `input-success`, `input-warning`, `input-error`
- **Styles**: `input-bordered`, `input-ghost`
- **Sizes**: `input-xs`, `input-sm`, `input-md`, `input-lg`

**Examples:**

```html
<!-- Basic input -->
<input type="text" placeholder="Type here" class="input input-bordered w-full max-w-xs" />

<!-- Colored inputs -->
<input type="text" placeholder="Primary" class="input input-bordered input-primary" />
<input type="text" placeholder="Secondary" class="input input-bordered input-secondary" />
<input type="text" placeholder="Accent" class="input input-bordered input-accent" />

<!-- State inputs -->
<input type="text" placeholder="Success" class="input input-bordered input-success" />
<input type="text" placeholder="Error" class="input input-bordered input-error" />

<!-- Sizes -->
<input type="text" placeholder="XS" class="input input-bordered input-xs" />
<input type="text" placeholder="SM" class="input input-bordered input-sm" />
<input type="text" placeholder="MD" class="input input-bordered input-md" />
<input type="text" placeholder="LG" class="input input-bordered input-lg" />

<!-- Disabled input -->
<input type="text" placeholder="Disabled" class="input input-bordered" disabled />
```

### Checkbox (`checkbox`)

**Base classes:** `checkbox`

**Modifiers:**
- **Colors**: `checkbox-primary`, `checkbox-secondary`, `checkbox-accent`
- **Sizes**: `checkbox-xs`, `checkbox-sm`, `checkbox-md`, `checkbox-lg`

**Examples:**

```html
<!-- Basic checkbox -->
<input type="checkbox" class="checkbox" />

<!-- Colored checkboxes -->
<input type="checkbox" class="checkbox checkbox-primary" checked />
<input type="checkbox" class="checkbox checkbox-secondary" checked />
<input type="checkbox" class="checkbox checkbox-accent" checked />

<!-- Sizes -->
<input type="checkbox" class="checkbox checkbox-xs" checked />
<input type="checkbox" class="checkbox checkbox-sm" checked />
<input type="checkbox" class="checkbox checkbox-md" checked />
<input type="checkbox" class="checkbox checkbox-lg" checked />

<!-- With label -->
<div class="form-control">
  <label class="label cursor-pointer">
    <span class="label-text">Remember me</span>
    <input type="checkbox" class="checkbox" />
  </label>
</div>
```

### Select (`select`)

**Base classes:** `select`

**Modifiers:**
- **Colors**: `select-primary`, `select-secondary`, `select-accent`
- **Styles**: `select-bordered`, `select-ghost`
- **Sizes**: `select-xs`, `select-sm`, `select-md`, `select-lg`

**Examples:**

```html
<!-- Basic select -->
<select class="select select-bordered w-full max-w-xs">
  <option disabled selected>Pick your favorite language</option>
  <option>Java</option>
  <option>Go</option>
  <option>C++</option>
</select>

<!-- Colored select -->
<select class="select select-bordered select-primary">
  <option>Option 1</option>
  <option>Option 2</option>
</select>

<!-- Sizes -->
<select class="select select-bordered select-xs">
  <option>XS</option>
</select>
<select class="select select-bordered select-sm">
  <option>SM</option>
</select>
<select class="select select-bordered select-md">
  <option>MD</option>
</select>
<select class="select select-bordered select-lg">
  <option>LG</option>
</select>
```

## Feedback

### Alert (`alert`)

**Base classes:** `alert`

**Modifiers:**
- **Types**: `alert-info`, `alert-success`, `alert-warning`, `alert-error`

**Examples:**

```html
<!-- Basic alert -->
<div class="alert">
  <span>Info alert message</span>
</div>

<!-- Alert types -->
<div class="alert alert-info">
  <svg class="stroke-current shrink-0 w-6 h-6">...</svg>
  <span>Info: Important information</span>
</div>

<div class="alert alert-success">
  <svg class="stroke-current shrink-0 w-6 h-6">...</svg>
  <span>Success: Your action was completed</span>
</div>

<div class="alert alert-warning">
  <svg class="stroke-current shrink-0 w-6 h-6">...</svg>
  <span>Warning: Please be careful</span>
</div>

<div class="alert alert-error">
  <svg class="stroke-current shrink-0 w-6 h-6">...</svg>
  <span>Error: Something went wrong</span>
</div>

<!-- Alert with actions -->
<div class="alert alert-warning">
  <svg class="stroke-current shrink-0 w-6 h-6">...</svg>
  <span>Warning: changes not saved</span>
  <div>
    <button class="btn btn-sm">Dismiss</button>
    <button class="btn btn-sm btn-primary">Save</button>
  </div>
</div>
```

### Loading (`loading`)

**Base classes:** `loading`

**Modifiers:**
- **Types**: `loading-spinner`, `loading-dots`, `loading-ring`, `loading-ball`, `loading-bars`, `loading-infinity`
- **Sizes**: `loading-xs`, `loading-sm`, `loading-md`, `loading-lg`

**Examples:**

```html
<!-- Loading indicators -->
<span class="loading loading-spinner"></span>
<span class="loading loading-dots"></span>
<span class="loading loading-ring"></span>
<span class="loading loading-ball"></span>
<span class="loading loading-bars"></span>
<span class="loading loading-infinity"></span>

<!-- Sizes -->
<span class="loading loading-spinner loading-xs"></span>
<span class="loading loading-spinner loading-sm"></span>
<span class="loading loading-spinner loading-md"></span>
<span class="loading loading-spinner loading-lg"></span>

<!-- Loading button -->
<button class="btn">
  <span class="loading loading-spinner"></span>
  Loading...
</button>

<!-- Loading in card -->
<div class="card bg-base-100 shadow-xl">
  <div class="card-body items-center">
    <span class="loading loading-spinner loading-lg"></span>
    <p>Loading content...</p>
  </div>
</div>
```

### Progress (`progress`)

**Base classes:** `progress`

**Modifiers:**
- **Colors**: `progress-primary`, `progress-secondary`, `progress-accent`
- **States**: `progress-info`, `progress-success`, `progress-warning`, `progress-error`

**Examples:**

```html
<!-- Basic progress -->
<progress class="progress w-56"></progress>

<!-- Progress with value -->
<progress class="progress w-56" value="70" max="100"></progress>

<!-- Colored progress -->
<progress class="progress progress-primary w-56" value="70" max="100"></progress>
<progress class="progress progress-secondary w-56" value="70" max="100"></progress>
<progress class="progress progress-accent w-56" value="70" max="100"></progress>

<!-- State progress -->
<progress class="progress progress-success w-56" value="70" max="100"></progress>
<progress class="progress progress-error w-56" value="70" max="100"></progress>
```

## Layout

### Divider (`divider`)

**Base classes:** `divider`

**Modifiers:**
- **Orientation**: `divider-horizontal`, `divider-vertical`

**Examples:**

```html
<!-- Horizontal divider -->
<div class="divider">OR</div>

<!-- Horizontal divider (no text) -->
<div class="divider"></div>

<!-- Vertical divider -->
<div class="flex">
  <div>Left content</div>
  <div class="divider divider-horizontal">OR</div>
  <div>Right content</div>
</div>
```

### Drawer (`drawer`)

**Base classes:** `drawer`

**Modifiers:**
- **Position**: `drawer-end`
- **Behavior**: `drawer-open`
- **Mobile**: `drawer-mobile` (deprecated, use `lg:drawer-open` instead)

**Structure:**
- `drawer` - Container
- `drawer-toggle` - Checkbox input for toggle
- `drawer-content` - Main content area
- `drawer-side` - Sidebar content
- `drawer-overlay` - Backdrop overlay

**Examples:**

```html
<!-- Basic drawer (sidebar) -->
<div class="drawer">
  <input id="my-drawer" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <!-- Page content here -->
    <label for="my-drawer" class="btn btn-primary drawer-button">Open drawer</label>
  </div>
  <div class="drawer-side">
    <label for="my-drawer" class="drawer-overlay"></label>
    <ul class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
      <!-- Sidebar content here -->
      <li><a>Sidebar Item 1</a></li>
      <li><a>Sidebar Item 2</a></li>
    </ul>
  </div>
</div>

<!-- Drawer that opens on large screens -->
<div class="drawer lg:drawer-open">
  <input id="my-drawer-2" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content flex flex-col items-center justify-center">
    <!-- Page content here -->
    <label for="my-drawer-2" class="btn btn-primary drawer-button lg:hidden">
      Open drawer
    </label>
  </div>
  <div class="drawer-side">
    <label for="my-drawer-2" class="drawer-overlay"></label>
    <ul class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
      <!-- Sidebar content here -->
      <li><a>Sidebar Item 1</a></li>
      <li><a>Sidebar Item 2</a></li>
    </ul>
  </div>
</div>

<!-- Drawer from right side -->
<div class="drawer drawer-end">
  <input id="my-drawer-4" type="checkbox" class="drawer-toggle" />
  <div class="drawer-content">
    <label for="my-drawer-4" class="drawer-button btn btn-primary">Open drawer</label>
  </div>
  <div class="drawer-side">
    <label for="my-drawer-4" class="drawer-overlay"></label>
    <ul class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
      <li><a>Sidebar Item 1</a></li>
      <li><a>Sidebar Item 2</a></li>
    </ul>
  </div>
</div>
```
