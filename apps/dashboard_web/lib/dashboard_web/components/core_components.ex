defmodule DashboardWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :show, :boolean, default: false

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      class="relative z-50 hidden"
    >
      <div class="fixed inset-0 bg-zinc-50/90 transition-opacity" />
      <div class="fixed inset-0 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(to: "##{id}")
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :title, :string, default: nil

  def flash(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, :info)} class="toast toast-top toast-end z-50">
      <div
        id="flash-info"
        phx-click={JS.push("lv:clear-flash", value: %{key: :info}) |> hide("#flash-info")}
        phx-mounted={show("#flash-info")}
        class="alert alert-info"
        role="alert"
      >
        <span class={["hero-information-circle", "stroke-current shrink-0 w-6 h-6"]} />
        <span><%= msg %></span>
        <button
          phx-click={JS.push("lv:clear-flash", value: %{key: :info}) |> hide("#flash-info")}
          class="btn btn-sm btn-ghost"
        >
          ✕
        </button>
      </div>
    </div>

    <div :if={msg = Phoenix.Flash.get(@flash, :error)} class="toast toast-top toast-end z-50">
      <div
        id="flash-error"
        phx-click={JS.push("lv:clear-flash", value: %{key: :error}) |> hide("#flash-error")}
        phx-mounted={show("#flash-error")}
        class="alert alert-error"
        role="alert"
      >
        <span class={["hero-x-circle", "stroke-current shrink-0 h-6 w-6"]} />
        <span><%= msg %></span>
        <button
          phx-click={JS.push("lv:clear-flash", value: %{key: :error}) |> hide("#flash-error")}
          class="btn btn-sm btn-ghost"
        >
          ✕
        </button>
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.flash flash={@flash} id="flash" />
    """
  end

  defp show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end
