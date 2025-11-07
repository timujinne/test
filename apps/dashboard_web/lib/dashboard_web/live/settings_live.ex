defmodule DashboardWeb.SettingsLive do
  use DashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-4">Settings</h1>
      <p class="text-gray-600">Settings interface coming soon...</p>
    </div>
    """
  end
end
