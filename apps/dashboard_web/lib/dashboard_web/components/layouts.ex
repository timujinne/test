defmodule DashboardWeb.Layouts do
  use DashboardWeb, :html

  import PhoenixKitWeb.Components.Core.ThemeController, only: [theme_controller: 1]
  import PhoenixKitWeb.Components.Core.UserInfo, only: [user_avatar: 1]

  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Routes

  embed_templates "layouts/*"

  # PhoenixKit calls app/1 - render public layout content
  # Handle both inner_content (from Phoenix) and inner_block (from PhoenixKit)
  slot :inner_block, required: false

  def app(assigns) do
    scope = assigns[:phoenix_kit_current_scope]

    user =
      cond do
        scope -> Scope.user(scope)
        assigns[:current_user] -> assigns[:current_user]
        true -> nil
      end

    is_admin = scope && (Scope.admin?(scope) || Scope.owner?(scope))

    assigns =
      assigns
      |> assign(:current_user, user)
      |> assign(:is_admin, is_admin)

    ~H"""
    <%!-- Public Layout for Blog and Auth Pages --%>
    <div class="min-h-screen flex flex-col">
      <%!-- Header (unified with PhoenixKit admin chrome) --%>
      <header class="navbar bg-base-100 shadow-md border-b border-base-300 sticky top-0 z-40">
        <div class="flex-1">
          <.link navigate="/news" class="btn btn-ghost gap-2">
            <img src={~p"/images/logo-48.png"} alt="Trading Blog" class="w-8 h-8" />
            <span class="text-xl font-semibold">Trading Blog</span>
          </.link>
        </div>

        <div class="flex-none flex items-center gap-2">
          <%!-- Theme Switcher (PhoenixKit core component) --%>
          <.theme_controller id="public-theme-dropdown" />

          <%= if @current_user do %>
            <%!-- Authenticated: user avatar dropdown --%>
            <div class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar">
                <.user_avatar user={@current_user} size="md" />
              </div>
              <ul
                tabindex="-1"
                class="dropdown-content menu menu-sm bg-base-100 rounded-box z-50 mt-3 w-52 p-2 shadow-lg border border-base-300"
              >
                <li>
                  <.link navigate="/dashboard/settings" class="gap-2">
                    <span class="hero-cog-6-tooth w-5 h-5" />
                    <span>Profile</span>
                  </.link>
                </li>
                <li :if={@is_admin}>
                  <.link href="/admin" class="gap-2">
                    <span class="hero-shield-check w-5 h-5" />
                    <span>Admin Panel</span>
                  </.link>
                </li>
                <li class="menu-title py-1">
                  <hr class="border-base-300" />
                </li>
                <li>
                  <.link
                    href={Routes.path("/users/log-out")}
                    method="delete"
                    class="gap-2 text-error hover:bg-error hover:text-error-content"
                  >
                    <span class="hero-arrow-left-end-on-rectangle w-5 h-5" />
                    <span>Logout</span>
                  </.link>
                </li>
              </ul>
            </div>
          <% else %>
            <%!-- Guest: login button --%>
            <.link href={Routes.path("/users/log-in")} class="btn btn-ghost btn-circle">
              <span class="hero-user w-6 h-6" />
            </.link>
          <% end %>
        </div>
      </header>

      <%!-- Flash Messages --%>
      <.flash_group flash={@flash} />

      <%!-- Main Content --%>
      <main class="flex-1 bg-base-200">
        <div class="container mx-auto px-4 py-8 max-w-6xl">
          <%= if @inner_block && @inner_block != [] do %>
            {render_slot(@inner_block)}
          <% else %>
            {@inner_content}
          <% end %>
        </div>
      </main>

      <%!-- Footer --%>
      <footer class="footer footer-center p-4 bg-base-100 text-base-content border-t border-base-300">
        <div>
          <p>Trading System Blog</p>
        </div>
      </footer>
    </div>
    """
  end

  # NOTE: trading_nav_link/1 and trading_nav_icon/1 are still used by the
  # trading_dashboard.html.heex layout, which is deleted in a later task.
  # They are kept here until that layout is removed to avoid breaking compilation.

  @doc """
  Navigation link component for trading dashboard sidebar.
  Supports both heroicon names and custom icon names.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, default: ""

  def trading_nav_link(assigns) do
    assigns = assign(assigns, :active, assigns.current_path == assigns.href)

    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-lg transition-colors",
        @active && "bg-primary text-primary-content",
        !@active && "text-base-content hover:bg-base-200"
      ]}
    >
      <.trading_nav_icon name={@icon} />
      <span>{@label}</span>
    </.link>
    """
  end

  @doc """
  Icon component for trading navigation.
  Uses custom trading icons from DashboardNav.
  """
  attr :name, :string, required: true

  def trading_nav_icon(assigns) do
    ~H"""
    <DashboardWeb.Components.DashboardNav.nav_icon name={@name} />
    """
  end
end
