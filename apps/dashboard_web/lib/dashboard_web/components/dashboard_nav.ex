defmodule DashboardWeb.Components.DashboardNav do
  @moduledoc """
  Dashboard navigation components for DaisyUI-based layout.

  Provides reusable navigation components including:
  - Navigation items with active state
  - Theme switcher
  """

  use Phoenix.Component

  @doc """
  Renders a navigation item with icon and label.

  ## Examples

      <.nav_item href="/trading" icon="chart" label="Trading" current_path={@current_path} />
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
        navigate={@href}
        class={[
          "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
          @active && "bg-primary text-primary-content font-semibold",
          !@active && "hover:bg-base-200"
        ]}
      >
        <.nav_icon name={@icon} />
        <span><%= @label %></span>
      </.link>
    </li>
    """
  end

  @doc """
  Renders an icon for navigation items.
  """
  attr :name, :string, required: true

  def nav_icon(assigns) do
    assigns = assign(assigns, :svg_path, icon_path(assigns.name))

    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <%= Phoenix.HTML.raw(@svg_path) %>
    </svg>
    """
  end

  # Icon SVG paths for Binance trading system
  defp icon_path("chart") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z" />
    """
  end

  defp icon_path("wallet") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
    """
  end

  defp icon_path("clock") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
    """
  end

  defp icon_path("settings") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    """
  end

  defp icon_path("strategy") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
    """
  end

  defp icon_path("orders") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
    """
  end

  defp icon_path("chain") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
    """
  end

  defp icon_path("blog") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M19 20H5a2 2 0 01-2-2V6a2 2 0 012-2h10a2 2 0 012 2v1m2 13a2 2 0 01-2-2V7m2 13a2 2 0 002-2V9a2 2 0 00-2-2h-2m-4-3H9M7 16h6M7 8h6v4H7V8z" />
    """
  end

  defp icon_path("user") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
    """
  end

  defp icon_path("shield") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
    """
  end

  defp icon_path("logout") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
    """
  end

  defp icon_path("key") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
    """
  end

  defp icon_path("home") do
    """
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
          d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
    """
  end

  defp icon_path(_), do: ""

  @doc """
  Renders the user menu dropdown with avatar support.

  Shows Admin Panel link only for users with admin or owner role.

  ## Attributes

  - `current_scope` - PhoenixKit current scope for avatar (optional)
  - `current_user` - Direct user object (fallback if scope not available)

  ## Examples

      <.user_menu />
      <.user_menu current_scope={@phoenix_kit_current_scope} />
      <.user_menu current_user={@current_user} />
  """
  attr :current_scope, :any, default: nil
  attr :current_user, :any, default: nil

  def user_menu(assigns) do
    # Get user from scope or fallback to current_user
    user =
      cond do
        assigns.current_scope ->
          PhoenixKit.Users.Auth.Scope.user(assigns.current_scope)

        assigns.current_user ->
          assigns.current_user

        true ->
          nil
      end

    avatar_file_id = user && user.custom_fields && user.custom_fields["avatar_file_id"]

    avatar_url =
      if avatar_file_id do
        PhoenixKit.Modules.Storage.URLSigner.signed_url(avatar_file_id, "medium")
      else
        nil
      end

    user_initials = get_user_initials(user)

    # Check if user is admin (only show admin panel for admins/owners)
    is_admin =
      cond do
        assigns.current_scope ->
          PhoenixKit.Users.Auth.Scope.admin?(assigns.current_scope) ||
            PhoenixKit.Users.Auth.Scope.owner?(assigns.current_scope)

        true ->
          false
      end

    assigns =
      assigns
      |> assign(:user, user)
      |> assign(:avatar_url, avatar_url)
      |> assign(:user_initials, user_initials)
      |> assign(:is_admin, is_admin)

    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        class="btn btn-ghost btn-circle avatar placeholder"
      >
        <div class="bg-neutral text-neutral-content w-10 rounded-full flex items-center justify-center overflow-hidden">
          <%= if @avatar_url do %>
            <img
              src={@avatar_url}
              alt="User avatar"
              class="w-full h-full object-cover"
              onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';"
            />
            <div class="hidden w-full h-full bg-neutral flex items-center justify-center text-neutral-content font-bold">
              <%= @user_initials %>
            </div>
          <% else %>
            <%= if @user do %>
              <span class="font-bold"><%= @user_initials %></span>
            <% else %>
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                />
              </svg>
            <% end %>
          <% end %>
        </div>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu menu-sm bg-base-100 rounded-box z-50 mt-3 w-52 p-2 shadow-lg border border-base-300"
      >
        <li>
          <.link navigate="/dashboard/settings" class="gap-2">
            <.nav_icon name="settings" />
            <span>Profile</span>
          </.link>
        </li>
        <li :if={@is_admin}>
          <.link href="/admin" class="gap-2">
            <.nav_icon name="shield" />
            <span>Admin Panel</span>
          </.link>
        </li>
        <li class="menu-title py-1">
          <hr class="border-base-300" />
        </li>
        <li>
          <.link
            href={PhoenixKit.Utils.Routes.path("/users/log-out")}
            method="delete"
            class="gap-2 text-error hover:bg-error hover:text-error-content"
          >
            <.nav_icon name="logout" />
            <span>Logout</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders the user menu for public pages (blog, etc.) with PhoenixKit auth support.

  Shows avatar with dropdown menu if authenticated, or login button if not.

  ## Attributes

  - `current_scope` - PhoenixKit current scope (phoenix_kit_current_scope)
  - `current_user` - PhoenixKit current user (phoenix_kit_current_user) - fallback if scope not available
  - `show_admin` - Whether to show the admin panel link (default: true in dev/test)

  ## Examples

      <.public_user_menu current_scope={@phoenix_kit_current_scope} />
      <.public_user_menu current_user={@phoenix_kit_current_user} />
  """
  attr :current_scope, :any, default: nil
  attr :current_user, :any, default: nil
  attr :show_admin, :boolean, default: Mix.env() in [:dev, :test]

  def public_user_menu(assigns) do
    # Get user from scope or fallback to current_user
    user =
      cond do
        assigns.current_scope ->
          PhoenixKit.Users.Auth.Scope.user(assigns.current_scope)

        assigns.current_user ->
          assigns.current_user

        true ->
          nil
      end

    avatar_file_id = user && user.custom_fields && user.custom_fields["avatar_file_id"]

    avatar_url =
      if avatar_file_id do
        PhoenixKit.Modules.Storage.URLSigner.signed_url(avatar_file_id, "medium")
      else
        nil
      end

    user_email = if user, do: user.email, else: nil
    user_initials = get_user_initials(user)
    authenticated? = user != nil

    assigns =
      assigns
      |> assign(:user, user)
      |> assign(:avatar_url, avatar_url)
      |> assign(:user_email, user_email)
      |> assign(:user_initials, user_initials)
      |> assign(:authenticated?, authenticated?)

    ~H"""
    <%= if @authenticated? do %>
      <%!-- Authenticated: show avatar dropdown --%>
      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost btn-circle avatar">
          <div class="w-10 rounded-full overflow-hidden bg-primary flex items-center justify-center text-primary-content font-bold">
            <%= if @avatar_url do %>
              <img
                src={@avatar_url}
                alt="User avatar"
                class="w-full h-full object-cover"
                onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';"
              />
              <div class="hidden w-full h-full bg-primary flex items-center justify-center text-primary-content font-bold">
                <%= @user_initials %>
              </div>
            <% else %>
              <%= @user_initials %>
            <% end %>
          </div>
        </label>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-sm bg-base-100 rounded-box z-50 mt-3 w-52 p-2 shadow-lg border border-base-300"
        >
          <li>
            <.link navigate="/app/trading" class="gap-2">
              <.nav_icon name="chart" />
              <span>Dashboard</span>
            </.link>
          </li>
          <li>
            <.link navigate="/dashboard/settings" class="gap-2">
              <.nav_icon name="settings" />
              <span>Profile</span>
            </.link>
          </li>
          <li :if={@show_admin}>
            <.link href="/admin" class="gap-2">
              <.nav_icon name="shield" />
              <span>Admin Panel</span>
            </.link>
          </li>
          <li class="menu-title py-1">
            <hr class="border-base-300" />
          </li>
          <li>
            <.link
              href={PhoenixKit.Utils.Routes.path("/users/log-out")}
              method="delete"
              class="gap-2 text-error hover:bg-error hover:text-error-content"
            >
              <.nav_icon name="logout" />
              <span>Logout</span>
            </.link>
          </li>
        </ul>
      </div>
    <% else %>
      <%!-- Not authenticated: show login button with user icon --%>
      <.link
        href={PhoenixKit.Utils.Routes.path("/users/log-in")}
        class="btn btn-ghost btn-circle avatar placeholder"
      >
        <div class="bg-neutral text-neutral-content w-10 rounded-full flex items-center justify-center">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
            />
          </svg>
        </div>
      </.link>
    <% end %>
    """
  end

  # Get user initials from name or email
  defp get_user_initials(nil), do: "?"

  defp get_user_initials(user) do
    cond do
      user.first_name && user.last_name ->
        "#{String.first(user.first_name)}#{String.first(user.last_name)}"
        |> String.upcase()

      user.first_name ->
        user.first_name |> String.first() |> String.upcase()

      user.email ->
        user.email |> String.first() |> String.upcase()

      true ->
        "?"
    end
  end

  @doc """
  Renders the theme switcher toggle.

  Uses the ThemeToggle LiveView hook for state management.
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
