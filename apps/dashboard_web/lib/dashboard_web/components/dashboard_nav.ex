defmodule DashboardWeb.Components.DashboardNav do
  @moduledoc """
  Dashboard navigation components for DaisyUI-based layout.

  Provides reusable navigation components including:
  - Navigation items with active state
  - Theme switcher
  """

  use Phoenix.Component
  alias Phoenix.HTML

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
    svg_path = icon_path(assigns.name)
    assigns = assign(assigns, :svg_path, Phoenix.HTML.raw(svg_path))

    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      {@svg_path}
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

  defp icon_path(_), do: ""

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
