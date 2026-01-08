defmodule DashboardWeb.Layouts do
  use DashboardWeb, :html

  embed_templates "layouts/*"

  # PhoenixKit calls app/1 - render public layout content
  # Handle both inner_content (from Phoenix) and inner_block (from PhoenixKit)
  slot :inner_block, required: false

  def app(assigns) do
    ~H"""
    <%!-- Public Layout for Blog and Auth Pages --%>
    <div class="min-h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar bg-base-100 shadow-md border-b border-base-300 sticky top-0 z-40">
        <div class="flex-1">
          <.link navigate="/articles" class="btn btn-ghost gap-2">
            <img src={~p"/images/logo-48.png"} alt="Trading Blog" class="w-8 h-8" />
            <span class="text-xl font-semibold">Trading Blog</span>
          </.link>
        </div>

        <div class="flex-none flex items-center gap-2">
          <%!-- Theme Switcher --%>
          <DashboardWeb.Components.DashboardNav.theme_switcher />
          <%!-- User Menu / Login --%>
          <DashboardWeb.Components.DashboardNav.public_user_menu
            current_scope={assigns[:phoenix_kit_current_scope]}
            current_user={assigns[:current_user]}
          />
        </div>
      </header>

      <%!-- Flash Messages --%>
      <.flash_group flash={@flash} />

      <%!-- Main Content --%>
      <main class="flex-1 bg-base-200">
        <div class="container mx-auto px-4 py-8 max-w-6xl">
          <%= if @inner_block && @inner_block != [] do %>
            <%= render_slot(@inner_block) %>
          <% else %>
            <%= @inner_content %>
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
      <span><%= @label %></span>
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
