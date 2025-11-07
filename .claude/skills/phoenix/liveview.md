---
name: phoenix-liveview
description: Generate Phoenix LiveView component with real-time updates and tests
tags: phoenix, liveview, elixir, real-time
---

# Generate Phoenix LiveView Component

This skill generates a complete Phoenix LiveView component with real-time functionality and tests.

## Step 1: Gather Requirements

Ask the user for:
1. **LiveView name** (e.g., `TradingLive`, `DashboardLive`)
2. **Route path** (e.g., `/trading`, `/dashboard`)
3. **Data to display** (e.g., trades, orders, portfolio)
4. **Real-time updates needed?** (PubSub integration)

## Step 2: Create LiveView Module

Create file at: `apps/dashboard_web/lib/dashboard_web/live/{name}_live.ex`

```elixir
defmodule DashboardWeb.{Component}Live do
  use DashboardWeb, :live_view

  require Logger

  @moduledoc """
  LiveView component for {description}.

  ## Real-time Updates

  Subscribes to PubSub topics for live data updates.
  """

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to PubSub if real-time updates needed
    if connected?(socket) do
      Phoenix.PubSub.subscribe(DashboardWeb.PubSub, "topic:updates")
    end

    socket =
      socket
      |> assign(:page_title, "{Page Title}")
      |> assign(:loading, true)
      |> assign(:data, [])
      |> assign(:filters, %{})
      |> load_initial_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    socket =
      socket
      |> assign(:filters, filters)
      |> apply_filters()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket = load_initial_data(socket)
    {:noreply, put_flash(socket, :info, "Data refreshed")}
  end

  @impl true
  def handle_event("filter", %{"field" => field, "value" => value}, socket) do
    filters = Map.put(socket.assigns.filters, field, value)

    socket =
      socket
      |> assign(:filters, filters)
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filters, %{})
      |> push_patch(to: build_path(socket, %{}))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_data, data}, socket) do
    # Handle real-time updates from PubSub
    socket = update(socket, :data, fn existing -> [data | existing] |> Enum.take(100) end)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:update_data, id, updates}, socket) do
    socket = update(socket, :data, fn data ->
      Enum.map(data, fn item ->
        if item.id == id, do: Map.merge(item, updates), else: item
      end)
    end)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <.header>
        {@page_title}
        <:subtitle>Real-time {description}</:subtitle>
        <:actions>
          <.button phx-click="refresh">
            <.icon name="hero-arrow-path" class="h-5 w-5" /> Refresh
          </.button>
        </:actions>
      </.header>

      <div class="mt-6">
        <%!-- Filters --%>
        <.form for={%{}} phx-change="filter" class="mb-6">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <.input
                type="text"
                name="field"
                value={@filters[:field]}
                placeholder="Filter by field..."
                phx-debounce="300"
              />
            </div>
            <div>
              <.button type="button" phx-click="clear_filters" variant="outline">
                Clear Filters
              </.button>
            </div>
          </div>
        </.form>

        <%!-- Data Display --%>
        <div :if={@loading} class="text-center py-12">
          <.spinner /> Loading...
        </div>

        <div :if={not @loading and @data == []} class="text-center py-12 text-gray-500">
          No data available
        </div>

        <div :if={not @loading and @data != []} class="space-y-4">
          <.table id="data-table" rows={@data}>
            <:col :let={item} label="ID">{item.id}</:col>
            <:col :let={item} label="Name">{item.name}</:col>
            <:col :let={item} label="Status">
              <.badge color={status_color(item.status)}>
                {item.status}
              </.badge>
            </:col>
            <:col :let={item} label="Created">
              {format_datetime(item.inserted_at)}
            </:col>
            <:action :let={item}>
              <.link navigate={~p"/items/#{item.id}"}>
                View
              </.link>
            </:action>
          </.table>
        </div>
      </div>
    </div>
    """
  end

  # Private Functions

  defp load_initial_data(socket) do
    # Load data from database or API
    # data = YourContext.list_items()
    data = []

    socket
    |> assign(:data, data)
    |> assign(:loading, false)
  end

  defp apply_filters(socket) do
    filters = socket.assigns.filters
    # Apply filters to data
    # filtered_data = YourContext.list_items(filters)

    assign(socket, :data, [])
  end

  defp parse_filters(params) do
    params
    |> Map.take(["field", "status", "date"])
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp build_path(socket, filters) do
    query_string = URI.encode_query(filters)

    base_path = socket.view
    |> to_string()
    |> String.split(".")
    |> List.last()
    |> String.replace("Live", "")
    |> String.downcase()

    if query_string == "" do
      "/#{base_path}"
    else
      "/#{base_path}?#{query_string}"
    end
  end

  defp status_color("active"), do: :green
  defp status_color("pending"), do: :yellow
  defp status_color("error"), do: :red
  defp status_color(_), do: :gray

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
end
```

## Step 3: Create Test File

Create file at: `apps/dashboard_web/test/dashboard_web/live/{name}_live_test.exs`

```elixir
defmodule DashboardWeb.{Component}LiveTest do
  use DashboardWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "successfully mounts and displays page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/{route}")

      assert html =~ "{Page Title}"
    end

    test "loads initial data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}")

      assert has_element?(lv, "#data-table")
    end
  end

  describe "handle_event/3 - refresh" do
    test "refreshes data on button click", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}")

      html = lv |> element("button", "Refresh") |> render_click()

      assert html =~ "Data refreshed"
    end
  end

  describe "handle_event/3 - filter" do
    test "applies filters and updates URL", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}")

      lv
      |> form("form", %{"field" => "test_value"})
      |> render_change()

      assert_patch(lv, ~p"/{route}?field=test_value")
    end

    test "clears filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}?field=test")

      lv |> element("button", "Clear Filters") |> render_click()

      assert_patch(lv, ~p"/{route}")
    end
  end

  describe "handle_info/2 - real-time updates" do
    test "receives and displays new data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}")

      new_data = %{id: 1, name: "Test Item", status: "active"}
      send(lv.pid, {:new_data, new_data})

      assert render(lv) =~ "Test Item"
    end

    test "updates existing data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/{route}")

      send(lv.pid, {:update_data, 1, %{status: "completed"}})

      assert render(lv) =~ "completed"
    end
  end
end
```

## Step 4: Add Route

Update `apps/dashboard_web/lib/dashboard_web/router.ex`:

```elixir
scope "/", DashboardWeb do
  pipe_through :browser

  live "/{route}", {Component}Live, :index
end
```

## Step 5: Add PubSub Broadcasting (if needed)

In your context or GenServer:

```elixir
defmodule YourApp.SomeContext do
  def create_item(attrs) do
    case Repo.insert(changeset) do
      {:ok, item} ->
        # Broadcast to LiveView
        Phoenix.PubSub.broadcast(
          DashboardWeb.PubSub,
          "topic:updates",
          {:new_data, item}
        )
        {:ok, item}

      error -> error
    end
  end
end
```

## Step 6: Run Tests

```bash
# Run LiveView tests
mix test apps/dashboard_web/test/dashboard_web/live/{name}_live_test.exs

# Run with coverage
mix test --cover
```

## Additional Features

### Add Loading States

```elixir
def handle_event("load_more", _params, socket) do
  {:noreply, assign(socket, :loading_more, true)}
end
```

### Add Pagination

```elixir
@impl true
def handle_event("load_more", _params, socket) do
  page = socket.assigns.page + 1
  new_data = load_data(page)

  socket =
    socket
    |> update(:data, fn data -> data ++ new_data end)
    |> assign(:page, page)

  {:noreply, socket}
end
```

### Add Search

```elixir
@impl true
def handle_event("search", %{"query" => query}, socket) do
  results = search_data(query)
  {:noreply, assign(socket, :data, results)}
end
```

## Best Practices

1. **Use `connected?/1`** to check if socket is connected before subscribing
2. **Debounce user input** with `phx-debounce` attribute
3. **Handle disconnections** gracefully
4. **Use `push_patch`** for URL updates without full page reload
5. **Limit real-time data** to prevent memory issues
6. **Add error boundaries** for robust error handling
