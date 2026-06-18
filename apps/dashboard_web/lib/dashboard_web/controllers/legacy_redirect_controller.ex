defmodule DashboardWeb.LegacyRedirectController do
  @moduledoc "Permanent redirects from legacy /app/* trading URLs to /admin/*."
  use DashboardWeb, :controller

  @map %{
    "trading" => "/admin/trading",
    "portfolio" => "/admin/portfolio",
    "orders" => "/admin/orders",
    "history" => "/admin/history",
    "strategies" => "/admin/strategies",
    "chains" => "/admin/chains",
    "accounts" => "/admin/accounts"
  }

  def show(conn, %{"page" => page}) when is_map_key(@map, page) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: Map.fetch!(@map, page))
    |> halt()
  end

  def show(conn, _params), do: redirect(conn, to: "/admin")
end
