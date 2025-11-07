defmodule DashboardWeb.PortfolioLive do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Portfolio", balances: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-4">Portfolio</h1>
      <p class="text-gray-600">Portfolio overview coming soon...</p>
    </div>
    """
  end
end
