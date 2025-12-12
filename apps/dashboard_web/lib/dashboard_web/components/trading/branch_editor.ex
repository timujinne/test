defmodule DashboardWeb.Components.Trading.BranchEditor do
  @moduledoc """
  Branch editor component for ConditionalChain strategy.
  Edits conditional branches with two paths based on price conditions.
  """
  use Phoenix.Component

  attr :branch, :map, required: true
  attr :index, :integer, required: true
  attr :editable, :boolean, default: true
  attr :on_delete, :string, default: nil
  attr :on_update, :string, default: nil
  attr :status, :string, default: "pending"

  @doc """
  Renders a conditional branch editor.

  ## Branch Structure
  %{
    condition: %{
      type: "price_change_percent",
      threshold_up: 1.0,
      threshold_down: -1.0
    },
    if_up: %{side: "SELL", quantity: "0.1", price: "market"},
    if_down: %{side: "BUY", quantity: "0.1", price: "market"}
  }

  ## Examples

      <.branch_editor
        branch=%{
          condition: %{threshold_up: 1.0, threshold_down: -1.0},
          if_up: %{side: "SELL", quantity: "0.1", price: "market"},
          if_down: %{side: "BUY", quantity: "0.1", price: "market"}
        }
        index={1}
        editable={true}
        on_delete="delete_branch"
        on_update="update_branch"
      />
  """
  def branch_editor(assigns) do
    assigns =
      assigns
      |> assign_new(:condition, fn -> Map.get(assigns.branch, :condition, %{}) end)
      |> assign_new(:if_up, fn -> Map.get(assigns.branch, :if_up, %{}) end)
      |> assign_new(:if_down, fn -> Map.get(assigns.branch, :if_down, %{}) end)

    ~H"""
    <div class={"card bg-base-100 border-2 border-warning " <> if(@status != "pending", do: "border-4", else: "")}>
      <div class="card-body p-4">
        <!-- Branch Header -->
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-2">
            <span class="badge badge-warning badge-sm">Conditional Branch</span>
            <span class="text-sm font-semibold text-base-content/60">
              Step <%= @index + 1 %>
            </span>
            <%= if @status != "pending" do %>
              <span class={"badge badge-sm " <> status_badge_class(@status)}>
                <%= status_label(@status) %>
              </span>
            <% end %>
          </div>

          <%= if @editable and @on_delete do %>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              phx-click={@on_delete}
              phx-value-index={@index}
              title="Delete branch"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          <% end %>
        </div>

        <!-- Condition Settings -->
        <div class="bg-base-200 rounded-lg p-3 mb-4">
          <h4 class="text-xs font-semibold text-base-content/70 mb-3">Condition Thresholds</h4>
          <div class="grid grid-cols-2 gap-3">
            <!-- Upward Threshold -->
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs">Price Up (%)</span>
              </label>
              <%= if @editable do %>
                <label class="input input-bordered input-sm flex items-center gap-2">
                  <span class="text-xs">+</span>
                  <input
                    type="text"
                    name={"branch_threshold_up_#{@index}"}
                    class="grow font-mono"
                    value={Map.get(@condition, :threshold_up, "1.0")}
                    phx-blur={@on_update}
                    phx-value-index={@index}
                    phx-value-field="threshold_up"
                    placeholder="1.0"
                    disabled={!@editable}
                  />
                  <span class="text-xs text-base-content/60">%</span>
                </label>
              <% else %>
                <div class="text-sm font-mono text-success">
                  +<%= Map.get(@condition, :threshold_up, "1.0") %>%
                </div>
              <% end %>
            </div>

            <!-- Downward Threshold -->
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs">Price Down (%)</span>
              </label>
              <%= if @editable do %>
                <label class="input input-bordered input-sm flex items-center gap-2">
                  <input
                    type="text"
                    name={"branch_threshold_down_#{@index}"}
                    class="grow font-mono"
                    value={Map.get(@condition, :threshold_down, "-1.0")}
                    phx-blur={@on_update}
                    phx-value-index={@index}
                    phx-value-field="threshold_down"
                    placeholder="-1.0"
                    disabled={!@editable}
                  />
                  <span class="text-xs text-base-content/60">%</span>
                </label>
              <% else %>
                <div class="text-sm font-mono text-error">
                  <%= Map.get(@condition, :threshold_down, "-1.0") %>%
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Branch Paths -->
        <div class="grid md:grid-cols-2 gap-4">
          <!-- IF UP Path -->
          <div class="card bg-success/10 border border-success/30">
            <div class="card-body p-3">
              <h4 class="text-xs font-semibold text-success flex items-center gap-1 mb-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 10l7-7m0 0l7 7m-7-7v18"
                  />
                </svg>
                If Price Rises
              </h4>

              <.branch_path_form
                path={@if_up}
                index={@index}
                path_type="if_up"
                editable={@editable}
                on_update={@on_update}
              />
            </div>
          </div>

          <!-- IF DOWN Path -->
          <div class="card bg-error/10 border border-error/30">
            <div class="card-body p-3">
              <h4 class="text-xs font-semibold text-error flex items-center gap-1 mb-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 14l-7 7m0 0l-7-7m7 7V3"
                  />
                </svg>
                If Price Falls
              </h4>

              <.branch_path_form
                path={@if_down}
                index={@index}
                path_type="if_down"
                editable={@editable}
                on_update={@on_update}
              />
            </div>
          </div>
        </div>

        <!-- Branch Visualization -->
        <%= if !@editable do %>
          <div class="mt-3 pt-3 border-t border-base-300">
            <div class="text-xs text-base-content/60 text-center">
              Waiting for price change: <%= Map.get(@condition, :threshold_up, "1.0") %>% up or <%= Map.get(
                @condition,
                :threshold_down,
                "-1.0"
              ) %>% down
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Branch path form component
  attr :path, :map, required: true
  attr :index, :integer, required: true
  attr :path_type, :string, required: true
  attr :editable, :boolean, required: true
  attr :on_update, :string, required: true

  defp branch_path_form(assigns) do
    ~H"""
    <div class="space-y-2">
      <!-- Side -->
      <div class="form-control">
        <label class="label py-0.5">
          <span class="label-text text-xs">Side</span>
        </label>
        <%= if @editable do %>
          <select
            name={"branch_#{@path_type}_side_#{@index}"}
            class={"select select-bordered select-sm " <> side_select_class(Map.get(@path, :side))}
            phx-change={@on_update}
            phx-value-index={@index}
            phx-value-field={"#{@path_type}_side"}
            disabled={!@editable}
          >
            <option value="BUY" selected={Map.get(@path, :side) == "BUY"}>BUY</option>
            <option value="SELL" selected={Map.get(@path, :side) == "SELL"}>SELL</option>
          </select>
        <% else %>
          <div class={"badge " <> side_badge_class(Map.get(@path, :side))}>
            <%= Map.get(@path, :side, "-") %>
          </div>
        <% end %>
      </div>

      <!-- Quantity -->
      <div class="form-control">
        <label class="label py-0.5">
          <span class="label-text text-xs">Quantity</span>
        </label>
        <%= if @editable do %>
          <input
            type="text"
            name={"branch_#{@path_type}_quantity_#{@index}"}
            class="input input-bordered input-sm font-mono"
            value={Map.get(@path, :quantity, "")}
            phx-blur={@on_update}
            phx-value-index={@index}
            phx-value-field={"#{@path_type}_quantity"}
            placeholder="0.001"
            disabled={!@editable}
          />
        <% else %>
          <div class="text-sm font-mono">
            <%= Map.get(@path, :quantity, "-") %>
          </div>
        <% end %>
      </div>

      <!-- Price -->
      <div class="form-control">
        <label class="label py-0.5">
          <span class="label-text text-xs">Price</span>
        </label>
        <%= if @editable do %>
          <input
            type="text"
            name={"branch_#{@path_type}_price_#{@index}"}
            class="input input-bordered input-sm font-mono"
            value={Map.get(@path, :price, "market")}
            phx-blur={@on_update}
            phx-value-index={@index}
            phx-value-field={"#{@path_type}_price"}
            placeholder="market or 42000"
            disabled={!@editable}
          />
        <% else %>
          <div class="text-sm font-mono">
            <%= Map.get(@path, :price, "market") %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp status_badge_class("active"), do: "badge-info"
  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_label("active"), do: "Active"
  defp status_label("completed"), do: "Completed"
  defp status_label("failed"), do: "Failed"
  defp status_label(_), do: "Pending"

  defp side_select_class("BUY"), do: "select-success"
  defp side_select_class("SELL"), do: "select-error"
  defp side_select_class(_), do: ""

  defp side_badge_class("BUY"), do: "badge-success"
  defp side_badge_class("SELL"), do: "badge-error"
  defp side_badge_class(_), do: "badge-ghost"
end
