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
    ~H"""
    <span class={[heroicon_class(@name), "w-5 h-5"]} />
    """
  end

  defp heroicon_class("chart"), do: "hero-chart-bar"
  defp heroicon_class("wallet"), do: "hero-wallet"
  defp heroicon_class("clock"), do: "hero-clock"
  defp heroicon_class("settings"), do: "hero-cog-6-tooth"
  defp heroicon_class("strategy"), do: "hero-presentation-chart-bar"
  defp heroicon_class("orders"), do: "hero-clipboard-document-list"
  defp heroicon_class("chain"), do: "hero-link"
  defp heroicon_class("blog"), do: "hero-newspaper"
  defp heroicon_class("user"), do: "hero-user"
  defp heroicon_class("shield"), do: "hero-shield-check"
  defp heroicon_class("logout"), do: "hero-arrow-left-end-on-rectangle"
  defp heroicon_class("key"), do: "hero-key"
  defp heroicon_class("home"), do: "hero-home"
  defp heroicon_class(_), do: "hero-ellipsis-horizontal"

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

    avatar_file_uuid = user && user.custom_fields && user.custom_fields["avatar_file_uuid"]

    avatar_url =
      if avatar_file_uuid do
        PhoenixKit.Modules.Storage.URLSigner.signed_url(avatar_file_uuid, "medium")
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
              <span class={["hero-user", "w-6 h-6"]} />
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

    avatar_file_uuid = user && user.custom_fields && user.custom_fields["avatar_file_uuid"]

    avatar_url =
      if avatar_file_uuid do
        PhoenixKit.Modules.Storage.URLSigner.signed_url(avatar_file_uuid, "medium")
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
          <span class={["hero-user", "w-6 h-6"]} />
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
      <span class={["swap-off", "hero-sun", "w-6 h-6"]} />

      <%!-- Moon icon (dark mode) --%>
      <span class={["swap-on", "hero-moon", "w-6 h-6"]} />
    </label>
    """
  end
end
