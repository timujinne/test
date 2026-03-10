defmodule DashboardWeb.PageController do
  use DashboardWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: "/news")
  end
end
