defmodule DashboardWeb.ChainsLive do
  @moduledoc """
  LiveView for managing ConditionalChain strategies.
  Provides interface for creating, monitoring, and controlling chain executions.
  """
  use DashboardWeb, :live_view

  import DashboardWeb.Components.Trading.ChainBuilder
  import DashboardWeb.Components.Trading.ChainMonitor

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to chain updates
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "chains:all")
      # Subscribe to price updates for active chains
      subscribe_to_active_chain_prices(socket)
    end

    socket =
      socket
      |> assign(page_title: "Conditional Chains")
      |> assign(current_path: "/app/chains")
      |> assign(user_id: nil)
      |> assign(show_builder: false)
      |> assign(builder_mode: "create")
      |> assign(editing_chain_id: nil)
      |> assign(chain_form: new_chain_form())
      |> assign(available_symbols: get_available_symbols())
      |> assign(saved_chains: [])
      |> assign(active_chains: [])
      |> assign(current_prices: %{})
      |> load_chains()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case params do
        %{"action" => "new"} ->
          socket
          |> assign(show_builder: true)
          |> assign(builder_mode: "create")
          |> assign(chain_form: new_chain_form())

        %{"action" => "edit", "id" => id} ->
          case find_chain(socket.assigns.saved_chains, id) do
            nil ->
              socket
              |> put_flash(:error, "Chain not found")
              |> assign(show_builder: false)

            chain ->
              socket
              |> assign(show_builder: true)
              |> assign(builder_mode: "edit")
              |> assign(editing_chain_id: id)
              |> assign(chain_form: chain_to_form(chain))
          end

        _ ->
          socket
          |> assign(show_builder: false)
          |> assign(builder_mode: "create")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_builder", %{"id" => id}, socket) do
    # Edit existing chain
    {:noreply, push_patch(socket, to: "/chains?action=edit&id=#{id}")}
  end

  @impl true
  def handle_event("show_builder", _params, socket) do
    # Create new chain
    {:noreply, push_patch(socket, to: "/chains?action=new")}
  end

  @impl true
  def handle_event("hide_builder", _params, socket) do
    {:noreply, push_patch(socket, to: "/chains")}
  end

  @impl true
  def handle_event("update_chain_field", params, socket) do
    # Get field from phx-value-field or derive from input name
    {field, value} =
      cond do
        # Direct value with field
        Map.has_key?(params, "field") and Map.has_key?(params, "value") ->
          {params["field"], params["value"]}

        # Named input: chain_name
        Map.has_key?(params, "chain_name") ->
          {"name", params["chain_name"]}

        # Named input: chain_symbol
        Map.has_key?(params, "chain_symbol") ->
          {"symbol", params["chain_symbol"]}

        # Named input: chain_initial_quantity
        Map.has_key?(params, "chain_initial_quantity") ->
          {"initial_quantity", params["chain_initial_quantity"]}

        # phx-value-field provided, find value from remaining params
        Map.has_key?(params, "field") ->
          val =
            params
            |> Map.drop(["field", "_target"])
            |> Map.values()
            |> List.first("")

          {params["field"], val}

        # Fallback - try to extract from any chain_* key
        true ->
          params
          |> Enum.find(fn {k, _v} -> String.starts_with?(to_string(k), "chain_") end)
          |> case do
            {key, val} -> {String.replace_prefix(to_string(key), "chain_", ""), val}
            nil -> {nil, ""}
          end
      end

    if field do
      field_atom = String.to_existing_atom(field)
      chain_form = Map.put(socket.assigns.chain_form, field_atom, value)
      {:noreply, assign(socket, chain_form: chain_form)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_step", %{"type" => type}, socket) do
    # Default symbol from form or first available symbol
    default_symbol = socket.assigns.chain_form[:symbol] ||
                     List.first(socket.assigns.available_symbols) ||
                     "BTCUSDT"

    new_step =
      case type do
        "step" ->
          %{type: "step", symbol: default_symbol, side: "BUY", quantity: "", price: ""}

        "branch" ->
          %{
            type: "branch",
            symbol: default_symbol,
            condition: %{threshold_up: "1.0", threshold_down: "-1.0"},
            if_up: %{symbol: default_symbol, side: "SELL", quantity: "", price: "market"},
            if_down: %{symbol: default_symbol, side: "BUY", quantity: "", price: "market"}
          }

        _ ->
          %{type: "step", symbol: default_symbol, side: "BUY", quantity: "", price: ""}
      end

    chain_form = socket.assigns.chain_form
    steps = Map.get(chain_form, :steps, [])
    updated_form = Map.put(chain_form, :steps, steps ++ [new_step])

    {:noreply, assign(socket, chain_form: updated_form)}
  end

  @impl true
  def handle_event("delete_step", %{"index" => index}, socket) do
    index = String.to_integer(index)
    chain_form = socket.assigns.chain_form
    steps = Map.get(chain_form, :steps, [])
    updated_steps = List.delete_at(steps, index)
    updated_form = Map.put(chain_form, :steps, updated_steps)

    {:noreply, assign(socket, chain_form: updated_form)}
  end

  @impl true
  def handle_event("update_step", params, socket) do
    index = params["index"] |> String.to_integer()
    field = params["field"]

    # Extract value from different input types
    value =
      cond do
        Map.has_key?(params, "value") ->
          params["value"]

        # Named step fields: step_side_0, step_quantity_0, etc
        true ->
          params
          |> Map.drop(["index", "field", "_target"])
          |> Map.values()
          |> List.first("")
      end

    chain_form = socket.assigns.chain_form
    steps = Map.get(chain_form, :steps, [])

    updated_steps =
      List.update_at(steps, index, fn step ->
        update_step_field(step, field, value)
      end)

    updated_form = Map.put(chain_form, :steps, updated_steps)

    {:noreply, assign(socket, chain_form: updated_form)}
  end

  @impl true
  def handle_event("save_chain", _params, socket) do
    chain_form = socket.assigns.chain_form

    case save_chain(chain_form, socket.assigns.builder_mode, socket.assigns.editing_chain_id) do
      {:ok, _chain} ->
        socket =
          socket
          |> put_flash(:info, "Chain saved successfully")
          |> push_patch(to: "/chains")
          |> load_chains()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save chain: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("start_chain", %{"id" => chain_id}, socket) do
    case start_chain_execution(chain_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Chain started successfully")
          |> load_chains()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start chain: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("stop_chain", %{"id" => chain_id}, socket) do
    case stop_chain_execution(chain_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Chain stopped successfully")
          |> load_chains()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop chain: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_chain", %{"id" => chain_id}, socket) do
    case cancel_chain_execution(chain_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Chain cancelled successfully")
          |> load_chains()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel chain: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_chain", %{"id" => chain_id}, socket) do
    case delete_saved_chain(chain_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Chain deleted successfully")
          |> load_chains()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete chain: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:ticker, %{symbol: symbol, price: price}}, socket) do
    current_prices = Map.put(socket.assigns.current_prices, symbol, price)
    {:noreply, assign(socket, current_prices: current_prices)}
  end

  @impl true
  def handle_info({:chain_update, _chain_data}, socket) do
    # Update active chains with new data
    socket = load_chains(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4 max-w-7xl">
      <!-- Page Header -->
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-3xl font-bold mb-2">Conditional Chains</h1>
          <p class="text-base-content/60">
            Create and manage multi-step trading chains with conditional branches
          </p>
        </div>

        <button
          type="button"
          class="btn btn-primary"
          phx-click="show_builder"
          disabled={@show_builder}
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
          New Chain
        </button>
      </div>

      <!-- Chain Builder (Modal or Section) -->
      <%= if @show_builder do %>
        <div class="mb-6">
          <.chain_builder
            chain={@chain_form}
            symbols={@available_symbols}
            on_save="save_chain"
            on_cancel="hide_builder"
            mode={@builder_mode}
          />
        </div>
      <% end %>

      <!-- Active Chains Section -->
      <%= if @active_chains != [] do %>
        <div class="mb-8">
          <h2 class="text-2xl font-bold mb-4 flex items-center gap-2">
            <span class="badge badge-success badge-lg">
              <%= length(@active_chains) %>
            </span>
            Active Chains
          </h2>

          <div class="space-y-4">
            <%= for chain <- @active_chains do %>
              <.chain_monitor
                chain={chain}
                current_price={Map.get(@current_prices, Map.get(chain, :symbol))}
                process_alive={check_process_alive(chain)}
                on_stop="stop_chain"
                on_cancel="cancel_chain"
              />
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Saved Chains Section -->
      <div>
        <h2 class="text-2xl font-bold mb-4">Saved Chains</h2>

        <%= if @saved_chains == [] do %>
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
            <span>No saved chains yet. Click "New Chain" to create your first conditional chain.</span>
          </div>
        <% else %>
          <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for chain <- @saved_chains do %>
              <.saved_chain_card
                chain={chain}
                on_start="start_chain"
                on_edit="show_builder"
                on_delete="delete_chain"
              />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Saved chain card component
  attr :chain, :map, required: true
  attr :on_start, :string, required: true
  attr :on_edit, :string, required: true
  attr :on_delete, :string, required: true

  defp saved_chain_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-lg border border-base-300 hover:border-primary transition-colors">
      <div class="card-body p-4">
        <div class="flex items-start justify-between mb-2">
          <h3 class="card-title text-lg"><%= Map.get(@chain, :name, "Unnamed") %></h3>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-ghost btn-sm btn-circle">
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
                  d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"
                />
              </svg>
            </label>
            <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52">
              <li>
                <a phx-click={@on_edit} phx-value-id={Map.get(@chain, :id)}>
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
                      d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                    />
                  </svg>
                  Edit
                </a>
              </li>
              <li>
                <a
                  phx-click={@on_delete}
                  phx-value-id={Map.get(@chain, :id)}
                  data-confirm="Are you sure you want to delete this chain?"
                  class="text-error"
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
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                  Delete
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div class="space-y-2 mb-4">
          <div class="flex items-center gap-2 flex-wrap">
            <%= for symbol <- (Map.get(@chain, :symbols) || [Map.get(@chain, :symbol, "-")]) do %>
              <span class="badge badge-info badge-sm">
                <%= symbol %>
              </span>
            <% end %>
            <span class="text-xs text-base-content/60">
              <%= Map.get(@chain, :steps, []) |> length() %> steps
            </span>
          </div>

          <%= if Map.get(@chain, :initial_quantity) do %>
            <div class="text-sm text-base-content/70">
              Initial: <span class="font-mono"><%= Map.get(@chain, :initial_quantity) %></span>
            </div>
          <% end %>
        </div>

        <div class="card-actions justify-end">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click={@on_start}
            phx-value-id={Map.get(@chain, :id)}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            Start
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp new_chain_form do
    %{
      name: "",
      symbol: "",
      initial_quantity: "",
      steps: []
    }
  end

  defp chain_to_form(chain) do
    %{
      name: Map.get(chain, :name, ""),
      symbol: Map.get(chain, :symbol, ""),
      initial_quantity: Map.get(chain, :initial_quantity, ""),
      steps: normalize_steps_keys(Map.get(chain, :steps, []))
    }
  end

  # Normalize string keys to atoms for UI components
  defp normalize_steps_keys(steps) when is_list(steps) do
    Enum.map(steps, &normalize_step_keys/1)
  end
  defp normalize_steps_keys(_), do: []

  defp normalize_step_keys(step) when is_map(step) do
    step
    |> Enum.map(fn {k, v} -> {to_atom_key(k), normalize_step_value(v)} end)
    |> Map.new()
  end
  defp normalize_step_keys(other), do: other

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key) when is_binary(key), do: String.to_atom(key)

  defp normalize_step_value(v) when is_map(v), do: normalize_step_keys(v)
  defp normalize_step_value(v), do: v

  defp find_chain(chains, id) do
    Enum.find(chains, fn chain -> Map.get(chain, :id) == id end)
  end

  defp update_step_field(step, field, value) do
    cond do
      # Branch condition fields
      String.starts_with?(field, "threshold_") ->
        condition = Map.get(step, :condition, %{})
        field_atom = String.to_existing_atom(String.replace_prefix(field, "", ""))
        updated_condition = Map.put(condition, field_atom, value)
        Map.put(step, :condition, updated_condition)

      # Branch path fields (if_up_*, if_down_*)
      String.starts_with?(field, "if_up_") ->
        path = Map.get(step, :if_up, %{})
        field_atom = String.to_existing_atom(String.replace_prefix(field, "if_up_", ""))
        updated_path = Map.put(path, field_atom, value)
        Map.put(step, :if_up, updated_path)

      String.starts_with?(field, "if_down_") ->
        path = Map.get(step, :if_down, %{})
        field_atom = String.to_existing_atom(String.replace_prefix(field, "if_down_", ""))
        updated_path = Map.put(path, field_atom, value)
        Map.put(step, :if_down, updated_path)

      # Regular step fields
      true ->
        field_atom = String.to_existing_atom(field)
        Map.put(step, field_atom, value)
    end
  end

  defp load_chains(socket) do
    # Get account_id from socket or fall back to default
    account_id = socket.assigns[:account_id] || get_default_account_id()

    if account_id do
      # Load saved chain settings (not yet started)
      saved_chains =
        SharedData.Settings.list_settings_by_account(account_id)
        |> Enum.filter(fn s -> s.strategy_name == "conditional_chain" end)
        |> Enum.map(&setting_to_chain/1)

      # Load active chain states
      active_chains =
        SharedData.ChainStates.list_chain_states_by_account(account_id)
        |> Enum.filter(fn cs -> cs.current_state not in ["completed", "error", "idle"] end)
        |> Enum.map(&chain_state_to_chain/1)

      socket
      |> assign(account_id: account_id)
      |> assign(saved_chains: saved_chains)
      |> assign(active_chains: active_chains)
    else
      socket
      |> assign(saved_chains: [])
      |> assign(active_chains: [])
    end
  end

  defp setting_to_chain(setting) do
    config = setting.config || %{}

    # Support both "steps" (new format) and "chain" (legacy format)
    steps = Map.get(config, "steps") || Map.get(config, "chain", []) |> normalize_steps()

    # Support both "symbols" (multi-symbol) and "symbol" (single)
    symbols = Map.get(config, "symbols") || [Map.get(config, "symbol", "BTCUSDT")]

    %{
      id: setting.id,
      name: Map.get(config, "name", "Chain #{setting.id |> String.slice(0..7)}"),
      symbol: Map.get(config, "symbol", List.first(symbols) || "BTCUSDT"),
      symbols: symbols,
      initial_quantity: Map.get(config, "initial_quantity", "0"),
      steps: steps,
      is_active: setting.is_active,
      account_id: setting.account_id
    }
  end

  defp chain_state_to_chain(chain_state) do
    setting = chain_state.setting
    config = setting.config || %{}

    %{
      id: chain_state.id,
      chain_id: chain_state.chain_id,
      setting_id: setting.id,
      name: Map.get(config, "name", "Chain #{chain_state.chain_id |> String.slice(0..7)}"),
      symbol: Map.get(config, "symbol", "BTCUSDT"),
      initial_quantity: chain_state.initial_quantity,
      current_quantity: chain_state.current_quantity,
      current_step_index: chain_state.current_step_index,
      current_state: chain_state.current_state,
      steps: Map.get(config, "chain", []) |> normalize_steps(),
      last_fill_price: chain_state.last_fill_price,
      reference_price: chain_state.reference_price,
      execution_history: chain_state.execution_history
    }
  end

  defp normalize_steps(steps) when is_list(steps), do: steps
  defp normalize_steps(_), do: []

  defp get_available_symbols do
    ["BTCUSDT", "ETHUSDT", "BNBUSDT", "ADAUSDT", "DOGEUSDT", "XRPUSDT", "SOLUSDT", "DOTUSDT", "MATICUSDT", "LTCUSDT", "MDTUSDT", "AXLUSDT"]
  end

  defp subscribe_to_active_chain_prices(socket) do
    active_chains = socket.assigns[:active_chains] || []

    active_chains
    |> Enum.map(fn chain -> Map.get(chain, :symbol) end)
    |> Enum.uniq()
    |> Enum.each(fn symbol ->
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "market:#{symbol}")
    end)

    :ok
  end

  defp check_process_alive(chain) do
    setting_id = Map.get(chain, :setting_id)
    if setting_id do
      case Registry.lookup(TradingEngine.TraderRegistry, setting_id) do
        [{_pid, _}] -> true
        [] -> false
      end
    else
      false
    end
  end

  # Strategy execution functions

  defp save_chain(chain_form, mode, editing_id) do
    account_id = get_default_account_id()

    if is_nil(account_id) do
      {:error, "No account found. Please create an account first in Settings."}
    else
      # Extract all unique symbols from steps for multi-symbol support
      symbols = extract_symbols_from_steps(chain_form.steps)
      steps_config = build_chain_config(chain_form.steps)

      config = %{
        "name" => chain_form.name,
        "symbol" => chain_form.symbol,  # Legacy: primary symbol
        "symbols" => symbols,            # Multi-symbol: all symbols used
        "initial_quantity" => chain_form.initial_quantity,
        "branch_threshold_percent" => "1.0",
        "steps" => steps_config,         # New format with per-step symbols
        "chain" => steps_config          # Legacy compatibility
      }

      case mode do
        "create" ->
          SharedData.Settings.create_setting(%{
            strategy_name: "conditional_chain",
            config: config,
            is_active: false,
            account_id: account_id
          })

        "edit" when is_binary(editing_id) ->
          case SharedData.Settings.get_setting(editing_id) do
            nil -> {:error, :not_found}
            setting -> SharedData.Settings.update_setting(setting, %{config: config})
          end

        _ ->
          {:error, :invalid_mode}
      end
    end
  end

  # Extract all unique symbols from steps
  defp extract_symbols_from_steps(nil), do: []
  defp extract_symbols_from_steps(steps) when not is_list(steps), do: []
  defp extract_symbols_from_steps(steps) do
    steps
    |> Enum.flat_map(fn step ->
      case get_step_field(step, :type, "step") do
        "branch" ->
          [
            get_in(step, [:if_up, :symbol]) || get_in(step, ["if_up", "symbol"]),
            get_in(step, [:if_down, :symbol]) || get_in(step, ["if_down", "symbol"]),
            get_step_field(step, :symbol, nil)
          ]
        _ ->
          [get_step_field(step, :symbol, nil)]
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp build_chain_config(nil), do: []
  defp build_chain_config(steps) when not is_list(steps), do: []

  defp build_chain_config(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      step_type = get_step_field(step, :type, "step")

      case step_type do
        "step" ->
          %{
            "type" => if(index == 0, do: "initial", else: "step"),
            "symbol" => get_step_field(step, :symbol, ""),  # Per-step symbol
            "side" => get_step_field(step, :side, "BUY"),
            "quantity" => get_step_field(step, :quantity, "0"),
            "price" => get_step_field(step, :price, "0")
          }

        "branch" ->
          if_up = get_step_field(step, :if_up, %{})
          if_down = get_step_field(step, :if_down, %{})

          %{
            "type" => "branch",
            "symbol" => get_step_field(step, :symbol, ""),  # Per-step symbol
            "price_rises" => %{
              "symbol" => get_step_field(if_up, :symbol, ""),
              "side" => get_step_field(if_up, :side, "SELL"),
              "quantity" => get_step_field(if_up, :quantity, "0"),
              "price" => get_step_field(if_up, :price, "market")
            },
            "price_falls" => %{
              "symbol" => get_step_field(if_down, :symbol, ""),
              "side" => get_step_field(if_down, :side, "BUY"),
              "quantity" => get_step_field(if_down, :quantity, "0"),
              "price" => get_step_field(if_down, :price, "market")
            }
          }

        _ ->
          %{"type" => "step", "symbol" => "", "side" => "BUY", "quantity" => "0", "price" => "0"}
      end
    end)
  end

  # Helper to get field from map with atom or string keys
  defp get_step_field(map, key, default) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp get_step_field(_, _, default), do: default

  defp start_chain_execution(setting_id) do
    case SharedData.Settings.get_setting(setting_id) do
      nil ->
        {:error, :not_found}

      setting ->
        # Activate the setting
        case SharedData.Settings.update_setting(setting, %{is_active: true}) do
          {:ok, updated_setting} ->
            # Start the trader for this setting
            TradingEngine.AccountSupervisor.start_trader(
              updated_setting.account_id,
              setting_id: updated_setting.id
            )

          error ->
            error
        end
    end
  end

  defp stop_chain_execution(chain_state_id) do
    case SharedData.ChainStates.get_chain_state(chain_state_id) do
      nil ->
        {:error, :not_found}

      chain_state ->
        setting = chain_state.setting

        # Deactivate the setting
        SharedData.Settings.update_setting(setting, %{is_active: false})

        # Stop the trader
        TradingEngine.AccountSupervisor.stop_trader(setting.id)

        {:ok, :stopped}
    end
  end

  defp cancel_chain_execution(chain_state_id) do
    case SharedData.ChainStates.get_chain_state(chain_state_id) do
      nil ->
        {:error, :not_found}

      chain_state ->
        # Update chain state to error/cancelled
        SharedData.ChainStates.update_chain_state(chain_state, %{
          current_state: "error",
          completed_at: DateTime.utc_now()
        })

        # Stop the trader if running
        setting = chain_state.setting
        TradingEngine.AccountSupervisor.stop_trader(setting.id)

        {:ok, :cancelled}
    end
  end

  defp delete_saved_chain(setting_id) do
    case SharedData.Settings.get_setting(setting_id) do
      nil -> {:error, :not_found}
      setting -> SharedData.Settings.delete_setting(setting)
    end
  end

  defp get_default_account_id do
    # Get first available account for now
    # In production, this should come from session/authentication
    case SharedData.Accounts.list_user_accounts(nil) |> List.first() do
      nil -> nil
      account -> account.id
    end
  end
end
