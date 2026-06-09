defmodule DashboardWeb.Components.Trading.ChainStep do
  @moduledoc """
  Chain step component for ConditionalChain strategy.
  Displays and edits single chain steps (initial, step, or branch).
  """
  use Phoenix.Component

  attr :step, :map, required: true
  attr :index, :integer, required: true
  attr :step_type, :string, default: "step"
  attr :editable, :boolean, default: true
  attr :on_delete, :string, default: nil
  attr :on_update, :string, default: nil
  attr :status, :string, default: "pending"
  attr :available_symbols, :list, default: []

  @doc """
  Renders a single chain step.

  ## Step Types
  - "initial" - First step with symbol and initial quantity
  - "step" - Regular buy/sell step
  - "branch" - Conditional branch (renders differently)

  ## Status
  - "pending" - Not yet executed
  - "active" - Currently executing
  - "completed" - Successfully completed
  - "failed" - Execution failed

  ## Examples

      <.chain_step
        step=%{side: "BUY", quantity: "0.1", price: "42000"}
        index={0}
        step_type="initial"
        editable={true}
        on_delete="delete_step"
        on_update="update_step"
        status="pending"
      />
  """
  def chain_step(assigns) do
    ~H"""
    <div class={"card bg-base-100 border-2 " <> status_border_class(@status)}>
      <div class="card-body p-4">
        <%!-- Step Header --%>
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <%!-- Step Type Badge --%>
            <span class={"badge badge-sm " <> step_type_badge_class(@step_type)}>
              {step_type_label(@step_type)}
            </span>

            <%!-- Step Number --%>
            <span class="text-sm font-semibold text-base-content/60">
              Step {@index + 1}
            </span>

            <%!-- Status Badge --%>
            <%= if @status != "pending" do %>
              <span class={"badge badge-sm " <> status_badge_class(@status)}>
                {status_label(@status)}
              </span>
            <% end %>
          </div>

          <%!-- Delete Button --%>
          <%= if @editable and @on_delete do %>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-circle"
              phx-click={@on_delete}
              phx-value-index={@index}
              title="Delete step"
            >
              <span class={["hero-x-mark", "h-4 w-4"]} />
            </button>
          <% end %>
        </div>

        <%!-- Initial Step Form --%>
        <%= if @step_type == "initial" do %>
          <div class="space-y-3">
            <%!-- Symbol --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Symbol</span>
              </label>
              <%= if @editable do %>
                <input
                  type="text"
                  class="input input-sm"
                  value={Map.get(@step, :symbol, "")}
                  phx-change={@on_update}
                  phx-value-index={@index}
                  phx-value-field="symbol"
                  placeholder="BTCUSDT"
                  disabled={!@editable}
                />
              <% else %>
                <div class="text-sm font-mono font-semibold">
                  {Map.get(@step, :symbol, "-")}
                </div>
              <% end %>
            </div>

            <%!-- Initial Quantity --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Initial Quantity</span>
              </label>
              <%= if @editable do %>
                <input
                  type="text"
                  class="input input-sm font-mono"
                  value={Map.get(@step, :quantity, "")}
                  phx-change={@on_update}
                  phx-value-index={@index}
                  phx-value-field="quantity"
                  placeholder="0.001"
                  disabled={!@editable}
                />
              <% else %>
                <div class="text-sm font-mono">
                  {Map.get(@step, :quantity, "-")}
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Regular Step Form --%>
        <%= if @step_type == "step" do %>
          <div class="grid grid-cols-4 gap-2">
            <%!-- Symbol (for multi-symbol chains) --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Symbol</span>
              </label>
              <%= if @editable do %>
                <%= if @available_symbols != [] do %>
                  <select
                    name={"step_symbol_#{@index}"}
                    class="select select-sm"
                    phx-change={@on_update}
                    phx-value-index={@index}
                    phx-value-field="symbol"
                    disabled={!@editable}
                  >
                    <%= for symbol <- @available_symbols do %>
                      <option value={symbol} selected={Map.get(@step, :symbol) == symbol}>
                        {symbol}
                      </option>
                    <% end %>
                  </select>
                <% else %>
                  <input
                    type="text"
                    name={"step_symbol_#{@index}"}
                    class="input input-sm font-mono"
                    value={Map.get(@step, :symbol, "")}
                    phx-blur={@on_update}
                    phx-value-index={@index}
                    phx-value-field="symbol"
                    placeholder="BTCUSDT"
                    disabled={!@editable}
                  />
                <% end %>
              <% else %>
                <div class="text-sm font-mono font-semibold">
                  {Map.get(@step, :symbol, "-")}
                </div>
              <% end %>
            </div>

            <%!-- Side --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Side</span>
              </label>
              <%= if @editable do %>
                <select
                  name={"step_side_#{@index}"}
                  class={"select select-sm " <> side_select_class(Map.get(@step, :side))}
                  phx-change={@on_update}
                  phx-value-index={@index}
                  phx-value-field="side"
                  disabled={!@editable}
                >
                  <option value="BUY" selected={Map.get(@step, :side) == "BUY"}>BUY</option>
                  <option value="SELL" selected={Map.get(@step, :side) == "SELL"}>SELL</option>
                </select>
              <% else %>
                <div class={"badge " <> side_badge_class(Map.get(@step, :side))}>
                  {Map.get(@step, :side, "-")}
                </div>
              <% end %>
            </div>

            <%!-- Quantity --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Quantity</span>
              </label>
              <%= if @editable do %>
                <input
                  type="text"
                  name={"step_quantity_#{@index}"}
                  class="input input-sm font-mono"
                  value={Map.get(@step, :quantity, "")}
                  phx-blur={@on_update}
                  phx-value-index={@index}
                  phx-value-field="quantity"
                  placeholder="0.001 or use_profit"
                  disabled={!@editable}
                />
              <% else %>
                <div class="text-sm font-mono">
                  {Map.get(@step, :quantity, "-")}
                </div>
              <% end %>
            </div>

            <%!-- Price --%>
            <div class="form-control">
              <label class="label py-1">
                <span class="label-text text-xs font-medium">Price</span>
              </label>
              <%= if @editable do %>
                <input
                  type="text"
                  name={"step_price_#{@index}"}
                  class="input input-sm font-mono"
                  value={Map.get(@step, :price, "")}
                  phx-blur={@on_update}
                  phx-value-index={@index}
                  phx-value-field="price"
                  placeholder="42000"
                  disabled={!@editable}
                />
              <% else %>
                <div class="text-sm font-mono">
                  {Map.get(@step, :price, "-")}
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- Execution Info (when not editable) --%>
        <%= if !@editable and @status == "completed" do %>
          <div class="mt-3 pt-3 border-t border-base-300">
            <div class="grid grid-cols-2 gap-2 text-xs">
              <%= if Map.get(@step, :executed_price) do %>
                <div>
                  <span class="text-base-content/60">Executed:</span>
                  <span class="font-mono ml-1">{Map.get(@step, :executed_price)}</span>
                </div>
              <% end %>
              <%= if Map.get(@step, :executed_at) do %>
                <div>
                  <span class="text-base-content/60">Time:</span>
                  <span class="font-mono ml-1">{format_time(Map.get(@step, :executed_at))}</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions for styling

  defp step_type_badge_class("initial"), do: "badge-primary"
  defp step_type_badge_class("step"), do: "badge-accent"
  defp step_type_badge_class("branch"), do: "badge-warning"
  defp step_type_badge_class(_), do: "badge-ghost"

  defp step_type_label("initial"), do: "Initial"
  defp step_type_label("step"), do: "Step"
  defp step_type_label("branch"), do: "Branch"
  defp step_type_label(_), do: "Unknown"

  defp status_border_class("pending"), do: "border-base-300"
  defp status_border_class("active"), do: "border-info border-4"
  defp status_border_class("completed"), do: "border-success"
  defp status_border_class("failed"), do: "border-error"
  defp status_border_class(_), do: "border-base-300"

  defp status_badge_class("active"), do: "badge-info"
  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_label("active"), do: "Active"
  defp status_label("completed"), do: "Completed"
  defp status_label("failed"), do: "Failed"
  defp status_label("pending"), do: "Pending"
  defp status_label(_), do: "Unknown"

  defp side_select_class("BUY"), do: "select-success"
  defp side_select_class("SELL"), do: "select-error"
  defp side_select_class(_), do: ""

  defp side_badge_class("BUY"), do: "badge-success"
  defp side_badge_class("SELL"), do: "badge-error"
  defp side_badge_class(_), do: "badge-ghost"

  defp format_time(nil), do: "-"

  defp format_time(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> datetime
    end
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "-"
end
