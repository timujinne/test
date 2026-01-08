defmodule DashboardWeb.Components.Trading.ChainMonitor do
  @moduledoc """
  Chain monitor component for ConditionalChain strategy.
  Shows real-time execution progress of active chains.
  """
  use Phoenix.Component

  import DashboardWeb.Components.Trading.ChainStep
  import DashboardWeb.Components.Trading.BranchEditor

  attr :chain, :map, required: true
  attr :current_price, :any, default: nil
  attr :on_stop, :string, default: nil
  attr :on_cancel, :string, default: nil
  attr :compact, :boolean, default: false
  attr :process_alive, :boolean, default: true

  @doc """
  Renders the chain execution monitor.

  ## Chain Structure
  %{
    id: "chain_123",
    name: "My Chain",
    symbol: "BTCUSDT",
    status: "active",
    current_step: 2,
    steps: [
      %{type: "step", side: "BUY", status: "completed", ...},
      %{type: "step", side: "SELL", status: "active", ...},
      %{type: "branch", status: "pending", ...}
    ],
    pnl: %{
      realized: 150.25,
      unrealized: -20.50,
      total: 129.75,
      percent: 1.29
    },
    started_at: ~U[2025-01-01 10:00:00Z]
  }

  ## Examples

      <.chain_monitor
        chain={@active_chain}
        current_price={42150.50}
        on_stop="stop_chain"
        on_cancel="cancel_chain"
      />
  """
  def chain_monitor(assigns) do
    assigns =
      assigns
      |> assign_new(:status, fn -> Map.get(assigns.chain, :status, "active") end)
      |> assign_new(:current_step, fn -> Map.get(assigns.chain, :current_step, 0) end)
      |> assign_new(:steps, fn -> Map.get(assigns.chain, :steps, []) end)
      |> assign_new(:pnl, fn -> Map.get(assigns.chain, :pnl, %{}) end)
      |> assign_new(:name, fn -> Map.get(assigns.chain, :name, "Unnamed Chain") end)
      |> assign_new(:symbol, fn -> Map.get(assigns.chain, :symbol, "") end)
      |> assign_new(:started_at, fn -> Map.get(assigns.chain, :started_at) end)
      |> assign_new(:execution_history, fn -> Map.get(assigns.chain, :execution_history, %{}) end)

    ~H"""
    <div class="card bg-base-100 shadow-xl border-2 border-info">
      <div class="card-body p-4">
        <!-- Header -->
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <h3 class="card-title text-lg">
              <%= @name %>
            </h3>
            <span class="badge badge-info">
              <%= @symbol %>
            </span>
            <span class={"badge " <> chain_status_badge_class(@status)}>
              <%= chain_status_label(@status) %>
            </span>
            <!-- Process Health Indicator -->
            <%= if @process_alive do %>
              <span class="badge badge-success badge-sm gap-1" title="Process running">
                <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
                Live
              </span>
            <% else %>
              <span class="badge badge-error badge-sm gap-1" title="Process not running">
                <span class="w-2 h-2 rounded-full bg-error"></span>
                Dead
              </span>
            <% end %>
          </div>

          <!-- Action Buttons -->
          <div class="flex gap-2">
            <%= if @on_stop && @status == "active" do %>
              <button
                type="button"
                class="btn btn-warning btn-sm"
                phx-click={@on_stop}
                phx-value-id={Map.get(@chain, :id)}
                title="Stop chain"
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
                    d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z"
                  />
                </svg>
                Stop
              </button>
            <% end %>

            <%= if @on_cancel && @status == "active" do %>
              <button
                type="button"
                class="btn btn-error btn-sm"
                phx-click={@on_cancel}
                phx-value-id={Map.get(@chain, :id)}
                title="Cancel chain"
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
                Cancel
              </button>
            <% end %>
          </div>
        </div>

        <!-- Progress Bar -->
        <div class="mb-4">
          <div class="flex items-center justify-between mb-1">
            <span class="text-xs text-base-content/60">
              Step <%= @current_step + 1 %> of <%= length(@steps) %>
            </span>
            <span class="text-xs font-semibold">
              <%= calculate_progress_percent(@current_step, @steps) %>%
            </span>
          </div>
          <progress
            class="progress progress-info w-full"
            value={@current_step + 1}
            max={length(@steps)}
          >
          </progress>
        </div>

        <!-- Current Price & PnL -->
        <div class="grid md:grid-cols-2 gap-4 mb-4">
          <!-- Current Price -->
          <%= if @current_price do %>
            <div class="card bg-base-200">
              <div class="card-body p-3">
                <div class="text-xs text-base-content/60 mb-1">Current Price</div>
                <div class="text-lg font-mono font-bold">
                  <%= format_price(@current_price) %>
                </div>
              </div>
            </div>
          <% end %>
          <!-- PnL Display -->
          <%= if @pnl != %{} do %>
            <div class={"card " <> pnl_bg_class(Map.get(@pnl, :total, 0))}>
              <div class="card-body p-3">
                <div class="text-xs text-base-content/60 mb-1">Total P&L</div>
                <div class="flex items-baseline gap-2">
                  <div class={"text-lg font-mono font-bold " <> pnl_text_class(Map.get(@pnl, :total, 0))}>
                    <%= format_pnl(Map.get(@pnl, :total, 0)) %>
                  </div>
                  <%= if Map.get(@pnl, :percent) do %>
                    <div class={"text-sm font-mono " <> pnl_text_class(Map.get(@pnl, :percent, 0))}>
                      (<%= format_percent(Map.get(@pnl, :percent)) %>%)
                    </div>
                  <% end %>
                </div>
                <!-- Realized/Unrealized breakdown -->
                <%= if Map.get(@pnl, :realized) || Map.get(@pnl, :unrealized) do %>
                  <div class="text-xs text-base-content/60 mt-1 space-y-0.5">
                    <%= if Map.get(@pnl, :realized) do %>
                      <div>
                        Realized: <span class="font-mono"><%= format_pnl(Map.get(@pnl, :realized)) %></span>
                      </div>
                    <% end %>
                    <%= if Map.get(@pnl, :unrealized) do %>
                      <div>
                        Unrealized: <span class="font-mono"><%= format_pnl(Map.get(@pnl, :unrealized)) %></span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Chain Info -->
        <%= if @started_at do %>
          <div class="text-xs text-base-content/60 mb-3">
            Started: <%= format_datetime(@started_at) %>
          </div>
        <% end %>

        <!-- Execution Timeline -->
        <%= if @execution_history != %{} and Map.get(@execution_history, "events", []) != [] do %>
          <div class="collapse collapse-arrow bg-base-200 mb-4">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-medium">
              Execution Timeline (<%= length(Map.get(@execution_history, "events", [])) %> events)
            </div>
            <div class="collapse-content">
              <ul class="timeline timeline-vertical timeline-compact">
                <%= for {event, idx} <- Enum.with_index(Enum.reverse(Map.get(@execution_history, "events", []))) do %>
                  <li>
                    <%= if idx > 0 do %><hr /><% end %>
                    <div class="timeline-start text-xs text-base-content/60">
                      <%= format_event_time(event["timestamp"]) %>
                    </div>
                    <div class="timeline-middle">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class={"h-4 w-4 " <> event_icon_class(event["type"])}>
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                      </svg>
                    </div>
                    <div class="timeline-end timeline-box text-xs">
                      <span class="font-semibold"><%= event_type_label(event["type"]) %></span>
                      <%= if event["data"] do %>
                        <div class="text-base-content/60 mt-1">
                          <%= format_event_data(event["data"]) %>
                        </div>
                      <% end %>
                    </div>
                    <%= if idx < length(Map.get(@execution_history, "events", [])) - 1 do %><hr /><% end %>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>

        <!-- Compact View Toggle -->
        <%= if !@compact do %>
          <!-- Steps List (Full View) -->
          <div class="space-y-3 mt-4">
            <div class="divider text-sm">Chain Steps</div>

            <%= for {step, index} <- Enum.with_index(@steps) do %>
              <div class="relative">
                <%= if Map.get(step, :type) == "branch" do %>
                  <.branch_editor
                    branch={step}
                    index={index}
                    editable={false}
                    status={step_status(step, index, @current_step, @status)}
                  />
                <% else %>
                  <.chain_step
                    step={step}
                    index={index}
                    step_type={Map.get(step, :type, "step")}
                    editable={false}
                    status={step_status(step, index, @current_step, @status)}
                  />
                <% end %>
                <!-- Arrow Connector -->
                <%= if index < length(@steps) - 1 do %>
                  <div class="flex justify-center my-2">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-5 w-5 text-base-content/20"
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
        <% else %>
          <!-- Compact Summary -->
          <div class="mt-3">
            <div class="stats stats-vertical lg:stats-horizontal shadow w-full">
              <div class="stat p-3">
                <div class="stat-title text-xs">Total Steps</div>
                <div class="stat-value text-2xl"><%= length(@steps) %></div>
              </div>

              <div class="stat p-3">
                <div class="stat-title text-xs">Completed</div>
                <div class="stat-value text-2xl text-success">
                  <%= count_completed_steps(@steps) %>
                </div>
              </div>

              <div class="stat p-3">
                <div class="stat-title text-xs">Remaining</div>
                <div class="stat-value text-2xl text-info">
                  <%= length(@steps) - count_completed_steps(@steps) %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp chain_status_badge_class("active"), do: "badge-success"
  defp chain_status_badge_class("awaiting_initial"), do: "badge-warning"
  defp chain_status_badge_class("awaiting_step"), do: "badge-info"
  defp chain_status_badge_class("awaiting_branch"), do: "badge-info"
  defp chain_status_badge_class("stopped"), do: "badge-warning"
  defp chain_status_badge_class("completed"), do: "badge-success"
  defp chain_status_badge_class("failed"), do: "badge-error"
  defp chain_status_badge_class("error"), do: "badge-error"
  defp chain_status_badge_class("cancelled"), do: "badge-error"
  defp chain_status_badge_class(_), do: "badge-ghost"

  defp chain_status_label("active"), do: "Active"
  defp chain_status_label("awaiting_initial"), do: "Awaiting Initial"
  defp chain_status_label("awaiting_step"), do: "Awaiting Step"
  defp chain_status_label("awaiting_branch"), do: "Awaiting Branch"
  defp chain_status_label("stopped"), do: "Stopped"
  defp chain_status_label("completed"), do: "Completed"
  defp chain_status_label("failed"), do: "Failed"
  defp chain_status_label("error"), do: "Error"
  defp chain_status_label("cancelled"), do: "Cancelled"
  defp chain_status_label(_), do: "Unknown"

  defp step_status(step, index, current_step, chain_status) do
    cond do
      # Use explicit step status if available
      Map.get(step, :status) -> Map.get(step, :status)
      # Current step is active only if chain is active
      index == current_step and chain_status == "active" -> "active"
      # Steps before current are completed
      index < current_step -> "completed"
      # Steps after current are pending
      true -> "pending"
    end
  end

  defp calculate_progress_percent(_current, []), do: 0

  defp calculate_progress_percent(current, steps) do
    ((current + 1) / length(steps) * 100) |> trunc()
  end

  defp count_completed_steps(steps) do
    Enum.count(steps, fn step ->
      Map.get(step, :status) == "completed"
    end)
  end

  defp pnl_bg_class(value) when value > 0, do: "bg-success/10 border border-success/30"
  defp pnl_bg_class(value) when value < 0, do: "bg-error/10 border border-error/30"
  defp pnl_bg_class(_), do: "bg-base-200"

  defp pnl_text_class(value) when value > 0, do: "text-success"
  defp pnl_text_class(value) when value < 0, do: "text-error"
  defp pnl_text_class(_), do: "text-base-content"

  defp format_price(price) when is_float(price) do
    :erlang.float_to_binary(price, decimals: 2)
  end

  defp format_price(price) when is_integer(price) do
    format_price(price * 1.0)
  end

  defp format_price(price) when is_binary(price), do: price
  defp format_price(_), do: "0.00"

  defp format_pnl(value) when is_number(value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(abs(value * 1.0), decimals: 2)}"
  end

  defp format_pnl(_), do: "0.00"

  defp format_percent(value) when is_number(value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(abs(value * 1.0), decimals: 2)}"
  end

  defp format_percent(_), do: "0.00"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> datetime
    end
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "-"

  # Timeline helper functions
  defp format_event_time(nil), do: "-"
  defp format_event_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> timestamp
    end
  end
  defp format_event_time(_), do: "-"

  defp event_type_label("order_placed"), do: "Order Placed"
  defp event_type_label("order_filled"), do: "Order Filled"
  defp event_type_label("branch_entered"), do: "Branch Entered"
  defp event_type_label("branch_taken"), do: "Branch Taken"
  defp event_type_label("chain_completed"), do: "Chain Completed"
  defp event_type_label("recovery"), do: "Recovered"
  defp event_type_label("termination"), do: "Terminated"
  defp event_type_label(type) when is_binary(type), do: String.capitalize(type)
  defp event_type_label(_), do: "Event"

  defp event_icon_class("order_filled"), do: "text-success"
  defp event_icon_class("chain_completed"), do: "text-info"
  defp event_icon_class("branch_taken"), do: "text-warning"
  defp event_icon_class("recovery"), do: "text-info"
  defp event_icon_class("termination"), do: "text-error"
  defp event_icon_class(_), do: "text-base-content/60"

  defp format_event_data(nil), do: ""
  defp format_event_data(data) when is_map(data) do
    data
    |> Enum.filter(fn {k, v} -> v != nil and k not in ["timestamp", "step_index"] end)
    |> Enum.map(fn {k, v} -> "#{format_key(k)}: #{v}" end)
    |> Enum.join(" | ")
  end
  defp format_event_data(_), do: ""

  defp format_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp format_key(key), do: to_string(key)
end
