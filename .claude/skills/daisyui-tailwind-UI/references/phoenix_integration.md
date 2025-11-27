# Phoenix LiveView Integration with DaisyUI

Best practices and patterns for integrating DaisyUI components with Phoenix LiveView.

## Component Architecture

### Creating Reusable Function Components

Define reusable UI components as Phoenix function components:

```elixir
defmodule MyAppWeb.CoreComponents do
  use Phoenix.Component

  @doc """
  Renders a DaisyUI button with various styles.

  ## Examples

      <.button>Default button</.button>
      <.button variant="primary">Primary button</.button>
      <.button size="sm" phx-click="action">Small button</.button>
  """
  attr :type, :string, default: "button"
  attr :variant, :string, default: "default", values: ~w(default primary secondary accent ghost link)
  attr :size, :string, default: "md", values: ~w(xs sm md lg)
  attr :outline, :boolean, default: false
  attr :loading, :boolean, default: false
  attr :rest, :global, include: ~w(disabled phx-click phx-value-id)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "btn",
        variant_class(@variant),
        size_class(@size),
        @outline && "btn-outline",
        @loading && "loading"
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  defp variant_class("primary"), do: "btn-primary"
  defp variant_class("secondary"), do: "btn-secondary"
  defp variant_class("accent"), do: "btn-accent"
  defp variant_class("ghost"), do: "btn-ghost"
  defp variant_class("link"), do: "btn-link"
  defp variant_class(_), do: ""

  defp size_class("xs"), do: "btn-xs"
  defp size_class("sm"), do: "btn-sm"
  defp size_class("lg"), do: "btn-lg"
  defp size_class(_), do: ""

  @doc """
  Renders a DaisyUI card component.
  """
  attr :class, :string, default: ""
  attr :title, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <div class={"card bg-base-100 shadow-xl", @class}>
      <div class="card-body">
        <h2 :if={@title} class="card-title"><%= @title %></h2>
        <%= render_slot(@inner_block) %>
        <div :if={@actions != []} class="card-actions justify-end">
          <%= render_slot(@actions) %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a DaisyUI alert component.
  """
  attr :type, :string, default: "info", values: ~w(info success warning error)
  attr :dismissible, :boolean, default: false
  slot :inner_block, required: true

  def alert(assigns) do
    ~H"""
    <div class={"alert", alert_type_class(@type)} role="alert">
      <svg class="stroke-current shrink-0 w-6 h-6" fill="none" viewBox="0 0 24 24">
        <%= alert_icon(@type) %>
      </svg>
      <span><%= render_slot(@inner_block) %></span>
      <button :if={@dismissible} class="btn btn-sm btn-ghost" phx-click="dismiss-alert">
        ✕
      </button>
    </div>
    """
  end

  defp alert_type_class("info"), do: "alert-info"
  defp alert_type_class("success"), do: "alert-success"
  defp alert_type_class("warning"), do: "alert-warning"
  defp alert_type_class("error"), do: "alert-error"

  defp alert_icon("info") do
    ~H"""
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    """
  end

  defp alert_icon("success") do
    ~H"""
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
    """
  end

  defp alert_icon("warning") do
    ~H"""
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
    """
  end

  defp alert_icon("error") do
    ~H"""
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
    """
  end
end
```

### Form Components

Create form input components with proper validation styling:

```elixir
@doc """
Renders a form input with label and error messages.
"""
attr :id, :string, required: true
attr :name, :string, required: true
attr :label, :string, required: true
attr :value, :any
attr :type, :string, default: "text"
attr :placeholder, :string, default: nil
attr :errors, :list, default: []
attr :help_text, :string, default: nil
attr :required, :boolean, default: false
attr :rest, :global

def input(assigns) do
  ~H"""
  <div class="form-control w-full">
    <label class="label" for={@id}>
      <span class="label-text">
        <%= @label %>
        <span :if={@required} class="text-error">*</span>
      </span>
    </label>
    <input
      type={@type}
      id={@id}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class={[
        "input input-bordered w-full",
        @errors != [] && "input-error"
      ]}
      {@rest}
    />
    <label :if={@help_text || @errors != []} class="label">
      <span :if={@help_text} class="label-text-alt"><%= @help_text %></span>
      <span :for={error <- @errors} class="label-text-alt text-error">
        <%= error %>
      </span>
    </label>
  </div>
  """
end

@doc """
Renders a select input with options.
"""
attr :id, :string, required: true
attr :name, :string, required: true
attr :label, :string, required: true
attr :value, :any
attr :options, :list, required: true
attr :prompt, :string, default: nil
attr :errors, :list, default: []
attr :rest, :global

def select_input(assigns) do
  ~H"""
  <div class="form-control w-full">
    <label class="label" for={@id}>
      <span class="label-text"><%= @label %></span>
    </label>
    <select
      id={@id}
      name={@name}
      class={[
        "select select-bordered w-full",
        @errors != [] && "select-error"
      ]}
      {@rest}
    >
      <option :if={@prompt} value="" disabled selected={@value == nil}>
        <%= @prompt %>
      </option>
      <%= for {label, value} <- @options do %>
        <option value={value} selected={value == @value}>
          <%= label %>
        </option>
      <% end %>
    </select>
    <label :if={@errors != []} class="label">
      <span :for={error <- @errors} class="label-text-alt text-error">
        <%= error %>
      </span>
    </label>
  </div>
  """
end

@doc """
Renders a checkbox input.
"""
attr :id, :string, required: true
attr :name, :string, required: true
attr :label, :string, required: true
attr :checked, :boolean, default: false
attr :rest, :global

def checkbox_input(assigns) do
  ~H"""
  <div class="form-control">
    <label class="label cursor-pointer justify-start gap-4">
      <input
        type="checkbox"
        id={@id}
        name={@name}
        checked={@checked}
        class="checkbox checkbox-primary"
        {@rest}
      />
      <span class="label-text"><%= @label %></span>
    </label>
  </div>
  """
end
```

## Modal Management

### Controlled Modal Pattern

Use LiveView assigns to control modal visibility:

```elixir
defmodule MyAppWeb.ItemLive.Index do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_modal, false)
     |> assign(:modal_item, nil)}
  end

  @impl true
  def handle_event("open_modal", %{"id" => id}, socket) do
    item = get_item(id)
    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:modal_item, item)}
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:modal_item, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <button class="btn btn-primary" phx-click="open_modal" phx-value-id="123">
        Open Modal
      </button>

      <!-- Modal -->
      <div class={["modal", @show_modal && "modal-open"]}>
        <div class="modal-box">
          <h3 class="font-bold text-lg"><%= @modal_item && @modal_item.title %></h3>
          <p class="py-4"><%= @modal_item && @modal_item.description %></p>
          <div class="modal-action">
            <button class="btn" phx-click="close_modal">Close</button>
            <button class="btn btn-primary" phx-click="save_item">Save</button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

### Modal Component

Create a reusable modal component:

```elixir
@doc """
Renders a modal dialog.
"""
attr :id, :string, required: true
attr :show, :boolean, default: false
attr :on_cancel, JS, default: %JS{}
attr :title, :string, default: nil

slot :inner_block, required: true
slot :actions

def modal(assigns) do
  ~H"""
  <div id={@id} class={["modal", @show && "modal-open"]}>
    <div class="modal-box">
      <button
        class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        phx-click={@on_cancel}
        type="button"
      >
        ✕
      </button>
      <h3 :if={@title} class="font-bold text-lg mb-4"><%= @title %></h3>
      <%= render_slot(@inner_block) %>
      <div :if={@actions != []} class="modal-action">
        <%= render_slot(@actions) %>
      </div>
    </div>
    <label class="modal-backdrop" phx-click={@on_cancel}></label>
  </div>
  """
end

# Usage
<.modal id="confirm-modal" show={@show_confirm} on_cancel={JS.push("close_confirm")}>
  <p>Are you sure you want to delete this item?</p>
  <:actions>
    <button class="btn" phx-click="close_confirm">Cancel</button>
    <button class="btn btn-error" phx-click="delete_item">Delete</button>
  </:actions>
</.modal>
```

## Loading States

### Showing Loading Indicators

```elixir
defmodule MyAppWeb.ItemLive.Index do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, loading: true)}
  end

  @impl true
  def handle_info(:loaded, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <div :if={@loading} class="flex items-center justify-center h-64">
        <span class="loading loading-spinner loading-lg"></span>
      </div>

      <div :if={!@loading}>
        <!-- Content here -->
      </div>
    </div>
    """
  end
end
```

### Button Loading State

```elixir
<button
  class={["btn btn-primary", @submitting && "loading"]}
  phx-click="submit_form"
  disabled={@submitting}
>
  <%= if @submitting, do: "Saving...", else: "Save" %>
</button>
```

## Flash Messages

### Converting Flash to Alerts

```elixir
# In your root layout or LiveView
def flash_alerts(assigns) do
  ~H"""
  <div class="toast toast-top toast-end z-50">
    <div
      :if={@flash["info"]}
      class="alert alert-info"
      phx-click="lv:clear-flash"
      phx-value-key="info"
    >
      <span><%= @flash["info"] %></span>
    </div>

    <div
      :if={@flash["error"]}
      class="alert alert-error"
      phx-click="lv:clear-flash"
      phx-value-key="error"
    >
      <span><%= @flash["error"] %></span>
    </div>

    <div
      :if={@flash["success"]}
      class="alert alert-success"
      phx-click="lv:clear-flash"
      phx-value-key="success"
    >
      <span><%= @flash["success"] %></span>
    </div>
  </div>
  """
end
```

## Data Tables

### Interactive Table with Actions

```elixir
def data_table(assigns) do
  ~H"""
  <div class="overflow-x-auto">
    <table class="table table-zebra">
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>Email</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= for item <- @items do %>
          <tr>
            <td><%= item.id %></td>
            <td><%= item.name %></td>
            <td><%= item.email %></td>
            <td>
              <div class="dropdown dropdown-end">
                <label tabindex="0" class="btn btn-ghost btn-xs">
                  Actions
                </label>
                <ul tabindex="0" class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52">
                  <li>
                    <a phx-click="edit" phx-value-id={item.id}>Edit</a>
                  </li>
                  <li>
                    <a phx-click="delete" phx-value-id={item.id} class="text-error">
                      Delete
                    </a>
                  </li>
                </ul>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <div :if={Enum.empty?(@items)} class="text-center py-12">
    <p class="text-base-content/50">No items found</p>
  </div>
  """
end
```

## Navigation

### Active Link Highlighting

```elixir
def nav_link(assigns) do
  ~H"""
  <li>
    <.link
      navigate={@href}
      class={[
        @active && "active"
      ]}
    >
      <%= render_slot(@inner_block) %>
    </.link>
  </li>
  """
end

# Usage
<ul class="menu menu-horizontal">
  <.nav_link href="/dashboard" active={@current_page == :dashboard}>
    Dashboard
  </.nav_link>
  <.nav_link href="/settings" active={@current_page == :settings}>
    Settings
  </.nav_link>
</ul>
```

## Drawer/Sidebar

### Responsive Sidebar with LiveView

```elixir
defmodule MyAppWeb.Layouts do
  use MyAppWeb, :html

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="main-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <!-- Navbar -->
        <div class="navbar bg-base-100 shadow-lg lg:hidden">
          <label for="main-drawer" class="btn btn-square btn-ghost">
            <svg class="w-6 h-6"><!-- hamburger icon --></svg>
          </label>
          <div class="flex-1">
            <a class="btn btn-ghost text-xl">MyApp</a>
          </div>
        </div>

        <!-- Main content -->
        <main class="flex-1 p-6">
          <.flash_alerts flash={@flash} />
          <%= @inner_content %>
        </main>
      </div>

      <!-- Sidebar -->
      <div class="drawer-side">
        <label for="main-drawer" class="drawer-overlay"></label>
        <aside class="menu p-4 w-80 min-h-full bg-base-200">
          <div class="mb-4">
            <h2 class="text-2xl font-bold">MyApp</h2>
          </div>
          <ul>
            <li><.link navigate="/dashboard">Dashboard</.link></li>
            <li><.link navigate="/items">Items</.link></li>
            <li><.link navigate="/settings">Settings</.link></li>
          </ul>
        </aside>
      </div>
    </div>
    """
  end
end
```

## Form Validation

### Real-time Validation with DaisyUI Styling

```elixir
defmodule MyAppWeb.ItemLive.Form do
  use MyAppWeb, :live_view
  alias MyApp.Items

  @impl true
  def mount(_params, _session, socket) do
    changeset = Items.change_item(%Items.Item{})
    {:ok, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"item" => item_params}, socket) do
    changeset =
      %Items.Item{}
      |> Items.change_item(item_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card w-full max-w-lg bg-base-100 shadow-xl mx-auto">
      <div class="card-body">
        <h2 class="card-title">Create Item</h2>

        <.form for={@form} phx-change="validate" phx-submit="save">
          <.input
            field={@form[:name]}
            label="Name"
            required
          />

          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
          />

          <.select_input
            field={@form[:category]}
            label="Category"
            options={[{"Technology", "tech"}, {"Design", "design"}]}
            prompt="Choose a category"
          />

          <div class="card-actions justify-end mt-4">
            <button type="submit" class="btn btn-primary">
              Create Item
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
```

## Performance Tips

1. **Use CSS classes conditionally** instead of JavaScript toggling when possible
2. **Leverage Phoenix.Component slots** for flexible, reusable components
3. **Use phx-update="ignore"** for static DaisyUI components that don't need re-rendering
4. **Keep modal content in assigns** to avoid re-rendering entire component tree
5. **Use phx-debounce** for search inputs and form validation

## Accessibility Considerations

1. **Always include proper labels** for form inputs using DaisyUI's `label` component
2. **Use semantic HTML** - DaisyUI components are built with accessibility in mind
3. **Add aria-labels** to icon-only buttons
4. **Ensure keyboard navigation** works for dropdowns and modals
5. **Test with screen readers** to verify component accessibility
