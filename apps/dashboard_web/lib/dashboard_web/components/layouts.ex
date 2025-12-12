defmodule DashboardWeb.Layouts do
  use DashboardWeb, :html

  embed_templates "layouts/*"

  # PhoenixKit calls app/1 for blog pages - delegate to drawer
  def app(assigns) do
    drawer(assigns)
  end
end
