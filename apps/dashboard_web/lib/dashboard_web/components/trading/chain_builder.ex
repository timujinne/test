defmodule DashboardWeb.Components.Trading.ChainBuilder do
  @moduledoc """
  Chain builder component for ConditionalChain strategy.
  Visual constructor for building order chains with steps and branches.
  """
  use Phoenix.Component

  import DashboardWeb.Components.Trading.ChainStep
  import DashboardWeb.Components.Trading.BranchEditor

  attr :chain, :map, required: true
  attr :symbols, :list, default: []
  attr :on_save, :string, default: nil
  attr :on_cancel, :string, default: nil
  attr :mode, :string, default: "create"

  @doc """
  Renders the chain builder interface.

  ## Chain Structure
  %{
    name: "My Chain",
    symbol: "BTCUSDT",
    initial_quantity: "0.1",
    steps: [
      %{type: "step", side: "BUY", quantity: "0.1", price: "42000"},
      %{type: "branch", condition: %{...}, if_up: %{...}, if_down: %{...}},
      %{type: "step", side: "SELL", quantity: "0.1", price: "43000"}
    ]
  }

  ## Examples

      <.chain_builder
        chain={@chain_form}
        symbols={@available_symbols}
        on_save="save_chain"
        on_cancel="cancel_builder"
        mode="create"
      />
  """
  def chain_builder(assigns) do
    assigns =
      assigns
      |> assign_new(:steps, fn -> Map.get(assigns.chain, :steps, []) end)
      |> assign_new(:name, fn -> Map.get(assigns.chain, :name, "") end)
      |> assign_new(:symbol, fn -> Map.get(assigns.chain, :symbol, "") end)
      |> assign_new(:initial_quantity, fn -> Map.get(assigns.chain, :initial_quantity, "") end)

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <!-- Header -->
        <div class="flex items-center justify-between mb-4">
          <h2 class="card-title">
            <%= if @mode == "create", do: "Create New Chain", else: "Edit Chain" %>
          </h2>
          <%= if @on_cancel do %>
            <button
              type="button"
              class="btn btn-ghost btn-sm btn-circle"
              phx-click={@on_cancel}
              title="Close"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
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

        <!-- Chain Configuration -->
        <div class="grid md:grid-cols-3 gap-4 mb-6">
          <!-- Chain Name -->
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Chain Name</span>
            </label>
            <input
              type="text"
              name="chain_name"
              class="input input-bordered"
              value={@name}
              phx-blur="update_chain_field"
              phx-value-field="name"
              placeholder="My Trading Chain"
            />
          </div>

          <!-- Symbol Selection -->
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Trading Symbol</span>
            </label>
            <%= if @symbols != [] do %>
              <select
                name="chain_symbol"
                class="select select-bordered"
                phx-change="update_chain_field"
                phx-value-field="symbol"
              >
                <option value="" selected={@symbol == ""}>Select symbol...</option>
                <%= for symbol <- @symbols do %>
                  <option value={symbol} selected={@symbol == symbol}>
                    <%= symbol %>
                  </option>
                <% end %>
              </select>
            <% else %>
              <input
                type="text"
                name="chain_symbol"
                class="input input-bordered"
                value={@symbol}
                phx-blur="update_chain_field"
                phx-value-field="symbol"
                placeholder="BTCUSDT"
              />
            <% end %>
          </div>

          <!-- Initial Quantity -->
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Initial Quantity</span>
            </label>
            <input
              type="text"
              name="chain_initial_quantity"
              class="input input-bordered font-mono"
              value={@initial_quantity}
              phx-blur="update_chain_field"
              phx-value-field="initial_quantity"
              placeholder="0.001"
            />
          </div>
        </div>

        <!-- Steps List -->
        <div class="mb-6">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-lg font-semibold">Chain Steps</h3>
            <div class="badge badge-outline">
              <%= length(@steps) %> steps
            </div>
          </div>

          <!-- Steps Container -->
          <%= if @steps == [] do %>
            <div class="alert alert-info">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="stroke-current shrink-0 w-6 h-6"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>No steps added yet. Click "Add Step" or "Add Branch" to start building your chain.</span>
            </div>
          <% else %>
            <div class="space-y-4">
              <%= for {step, index} <- Enum.with_index(@steps) do %>
                <div class="relative">
                  <!-- Step Component -->
                  <%= if Map.get(step, :type) == "branch" do %>
                    <.branch_editor
                      branch={step}
                      index={index}
                      editable={true}
                      on_delete="delete_step"
                      on_update="update_step"
                    />
                  <% else %>
                    <.chain_step
                      step={step}
                      index={index}
                      step_type={Map.get(step, :type, "step")}
                      editable={true}
                      available_symbols={@symbols}
                      on_delete="delete_step"
                      on_update="update_step"
                    />
                  <% end %>
                  <!-- Arrow Connector -->
                  <%= if index < length(@steps) - 1 do %>
                    <div class="flex justify-center my-2">
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-6 w-6 text-base-content/30"
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
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Add Step Buttons -->
        <div class="flex gap-3 mb-6">
          <button
            type="button"
            class="btn btn-outline btn-primary flex-1"
            phx-click="add_step"
            phx-value-type="step"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 4v16m8-8H4"
              />
            </svg>
            Add Step
          </button>

          <button
            type="button"
            class="btn btn-outline btn-warning flex-1"
            phx-click="add_step"
            phx-value-type="branch"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
              />
            </svg>
            Add Branch
          </button>
        </div>

        <!-- Divider -->
        <div class="divider"></div>

        <!-- Action Buttons -->
        <div class="flex gap-3 justify-end">
          <%= if @on_cancel do %>
            <button type="button" class="btn btn-ghost" phx-click={@on_cancel}>
              Cancel
            </button>
          <% end %>

          <%= if @on_save do %>
            <button
              type="button"
              class="btn btn-success"
              phx-click={@on_save}
              disabled={!is_valid_chain?(@chain)}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                />
              </svg>
              <%= if @mode == "create", do: "Create Chain", else: "Save Changes" %>
            </button>
          <% end %>
        </div>

        <!-- Validation Messages -->
        <%= if !is_valid_chain?(@chain) do %>
          <div class="alert alert-warning mt-4">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
            <div>
              <div class="font-bold">Chain is incomplete</div>
              <div class="text-sm"><%= validation_message(@chain) %></div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Validation helpers

  defp is_valid_chain?(chain) do
    has_name?(chain) and has_symbol?(chain) and has_initial_quantity?(chain) and has_steps?(chain)
  end

  defp has_name?(chain) do
    name = Map.get(chain, :name, "")
    is_binary(name) and String.trim(name) != ""
  end

  defp has_symbol?(chain) do
    symbol = Map.get(chain, :symbol, "")
    is_binary(symbol) and String.trim(symbol) != ""
  end

  defp has_initial_quantity?(chain) do
    quantity = Map.get(chain, :initial_quantity, "")

    case Float.parse(to_string(quantity)) do
      {value, ""} when value > 0 -> true
      _ -> false
    end
  end

  defp has_steps?(chain) do
    steps = Map.get(chain, :steps, [])
    is_list(steps) and length(steps) > 0
  end

  defp validation_message(chain) do
    cond do
      !has_name?(chain) -> "Please provide a chain name"
      !has_symbol?(chain) -> "Please select or enter a trading symbol"
      !has_initial_quantity?(chain) -> "Please provide a valid initial quantity"
      !has_steps?(chain) -> "Please add at least one step to the chain"
      true -> "Please complete all required fields"
    end
  end
end
