defmodule DashboardWeb.StrategiesLive do
  use DashboardWeb, :live_view

  alias SharedData.Repo
  alias SharedData.Schemas.Setting
  alias SharedData.{Accounts, Settings}
  alias DashboardWeb.Live.UserContext

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to strategy lifecycle events
      Phoenix.PubSub.subscribe(BinanceSystem.PubSub, "strategies:all")

      # Fallback status check every 60 seconds (main updates come via PubSub events)
      :timer.send_interval(60_000, self(), :check_trader_status)
    end

    socket =
      socket
      |> UserContext.assign_user_context()
      |> assign(page_title: "Strategies")
      |> assign(current_path: "/app/strategies")
      |> assign(accounts: [])
      |> assign(strategies: [])
      |> assign(running_strategies: %{})
      # Strategy form state
      |> assign(show_strategy_form: false)
      |> assign(editing_strategy: nil)
      |> assign(strategy_form: nil)
      |> assign(selected_strategy_type: nil)
      |> assign(available_strategies: Settings.available_strategies())
      |> load_data()
      |> sync_running_strategies()

    {:ok, socket}
  end

  @impl true
  def handle_event("activate_strategy", %{"id" => strategy_id}, socket) do
    case activate_strategy(strategy_id) do
      {:ok, _strategy} ->
        socket =
          socket
          |> put_flash(:info, "Strategy activated successfully")
          |> load_data()
          |> sync_running_strategies()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to activate strategy: #{reason}")}
    end
  end

  @impl true
  def handle_event("deactivate_strategy", %{"id" => strategy_id}, socket) do
    case deactivate_strategy(strategy_id) do
      {:ok, _strategy} ->
        socket =
          socket
          |> put_flash(:info, "Strategy stopped successfully")
          |> load_data()
          |> sync_running_strategies()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop strategy: #{reason}")}
    end
  end

  @impl true
  def handle_event("select_strategy_type", %{"type" => strategy_type}, socket) do
    default_config = Settings.default_config_for(strategy_type)

    changeset =
      Settings.change_setting(%Setting{}, %{
        strategy_name: strategy_type,
        config: default_config
      })

    socket =
      socket
      |> assign(show_strategy_form: true)
      |> assign(editing_strategy: nil)
      |> assign(selected_strategy_type: strategy_type)
      |> assign(strategy_form: to_form(changeset, as: "setting"))

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_strategy_form", _params, socket) do
    socket =
      socket
      |> assign(show_strategy_form: false)
      |> assign(editing_strategy: nil)
      |> assign(strategy_form: nil)
      |> assign(selected_strategy_type: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_strategy", %{"id" => strategy_id}, socket) do
    case Settings.get_setting_by_user(strategy_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Strategy not found")}

      strategy ->
        changeset = Settings.change_setting(strategy)

        socket =
          socket
          |> assign(show_strategy_form: true)
          |> assign(editing_strategy: strategy)
          |> assign(selected_strategy_type: strategy.strategy_name)
          |> assign(strategy_form: to_form(changeset, as: "setting"))

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_strategy", %{"setting" => params}, socket) do
    # Parse config from form
    params = parse_strategy_config(params)

    changeset =
      case socket.assigns.editing_strategy do
        nil ->
          %Setting{}
          |> Settings.change_setting(params)
          |> Map.put(:action, :validate)

        strategy ->
          strategy
          |> Settings.change_setting(params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign(socket, strategy_form: to_form(changeset, as: "setting"))}
  end

  @impl true
  def handle_event("save_strategy", %{"setting" => params}, socket) do
    params = parse_strategy_config(params)

    case socket.assigns.editing_strategy do
      nil ->
        case Settings.create_setting(params) do
          {:ok, setting} ->
            # If strategy is active, notify StrategyManager to start it
            if setting.is_active do
              Phoenix.PubSub.broadcast(
                BinanceSystem.PubSub,
                "strategy_updates",
                {:strategy_activated, setting}
              )
            end

            socket =
              socket
              |> put_flash(:info, "Strategy created successfully")
              |> assign(show_strategy_form: false)
              |> assign(strategy_form: nil)
              |> assign(selected_strategy_type: nil)
              |> load_data()

            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, strategy_form: to_form(changeset, as: "setting"))}
        end

      strategy ->
        was_active = strategy.is_active

        case Settings.update_setting(strategy, params) do
          {:ok, updated_setting} ->
            # Handle activation/deactivation on update
            cond do
              updated_setting.is_active and not was_active ->
                Phoenix.PubSub.broadcast(
                  BinanceSystem.PubSub,
                  "strategy_updates",
                  {:strategy_activated, updated_setting}
                )

              not updated_setting.is_active and was_active ->
                Phoenix.PubSub.broadcast(
                  BinanceSystem.PubSub,
                  "strategy_updates",
                  {:strategy_deactivated, updated_setting}
                )

              true ->
                :ok
            end

            socket =
              socket
              |> put_flash(:info, "Strategy updated successfully")
              |> assign(show_strategy_form: false)
              |> assign(editing_strategy: nil)
              |> assign(strategy_form: nil)
              |> assign(selected_strategy_type: nil)
              |> load_data()

            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, strategy_form: to_form(changeset, as: "setting"))}
        end
    end
  end

  @impl true
  def handle_event("delete_strategy", %{"id" => strategy_id}, socket) do
    case Settings.get_setting_by_user(strategy_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Strategy not found")}

      strategy ->
        case Settings.delete_setting(strategy) do
          {:ok, _setting} ->
            socket =
              socket
              |> put_flash(:info, "Strategy deleted successfully")
              |> load_data()

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete strategy")}
        end
    end
  end

  @impl true
  def handle_info({:strategy_started, setting_id, _state}, socket) do
    # Mark strategy as running (event-driven update)
    running_strategies = Map.put(socket.assigns.running_strategies, setting_id, true)

    socket =
      socket
      |> assign(running_strategies: running_strategies)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:strategy_stopped, setting_id}, socket) do
    # Remove from running strategies (event-driven update)
    running_strategies = Map.delete(socket.assigns.running_strategies, setting_id)

    socket =
      socket
      |> assign(running_strategies: running_strategies)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:strategy_error, setting_id, reason}, socket) do
    # Remove from running strategies and show error
    running_strategies = Map.delete(socket.assigns.running_strategies, setting_id)

    socket =
      socket
      |> assign(running_strategies: running_strategies)
      |> put_flash(:error, "Strategy error: #{inspect(reason)}")
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:check_trader_status, socket) do
    # Fallback sync every 60s to catch any missed events
    {:noreply, sync_running_strategies(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp parse_strategy_config(params) do
    # Handle is_active boolean conversion
    params =
      Map.update(params, "is_active", false, fn
        "true" -> true
        "false" -> false
        true -> true
        false -> false
        "on" -> true
        _ -> false
      end)

    # Extract all config_ prefixed fields
    config_params =
      params
      |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "config_") end)
      |> Enum.map(fn {k, v} ->
        key = String.replace_prefix(k, "config_", "")
        {key, v}
      end)
      |> Enum.into(%{})

    # Build base config (non-condition fields)
    base_config =
      config_params
      |> Enum.reject(fn {k, _} ->
        String.starts_with?(k, "start_") or String.starts_with?(k, "stop_")
      end)
      |> Enum.map(fn {k, v} -> {k, parse_config_value(v)} end)
      |> Enum.into(%{})

    # Build start_conditions
    start_conditions = build_start_conditions(config_params)

    # Build stop_conditions
    stop_conditions = build_stop_conditions(config_params)

    # Merge conditions into config if they have any enabled conditions
    config =
      base_config
      |> maybe_add_conditions("start_conditions", start_conditions)
      |> maybe_add_conditions("stop_conditions", stop_conditions)

    params
    |> Map.drop(
      Enum.map(Map.keys(params), fn k ->
        if String.starts_with?(k, "config_"), do: k, else: nil
      end)
      |> Enum.reject(&is_nil/1)
    )
    |> Map.put("config", config)
  end

  defp parse_config_value(v) when is_binary(v) do
    case Float.parse(v) do
      {num, ""} ->
        num

      _ ->
        case Integer.parse(v) do
          {num, ""} -> num
          _ -> v
        end
    end
  end

  defp parse_config_value(v), do: v

  defp build_start_conditions(params) do
    conditions = []

    # Price condition
    conditions =
      if is_enabled?(params["start_price_enabled"]) do
        price_value = parse_config_value(params["start_price_value"])

        if price_value && price_value != "" do
          condition = %{
            "type" => "price",
            "operator" => params["start_price_op"] || "below",
            "value" => price_value
          }

          [condition | conditions]
        else
          conditions
        end
      else
        conditions
      end

    # Time condition
    conditions =
      if is_enabled?(params["start_time_enabled"]) do
        condition = %{
          "type" => "time",
          "start_hour" => parse_config_value(params["start_time_from"]) || 9,
          "end_hour" => parse_config_value(params["start_time_to"]) || 17
        }

        [condition | conditions]
      else
        conditions
      end

    # Volume condition
    conditions =
      if is_enabled?(params["start_volume_enabled"]) do
        volume_value = parse_config_value(params["start_volume_value"])

        if volume_value && volume_value != "" do
          condition = %{
            "type" => "volume",
            "operator" => params["start_volume_op"] || "above",
            "value" => volume_value
          }

          [condition | conditions]
        else
          conditions
        end
      else
        conditions
      end

    if Enum.empty?(conditions) do
      nil
    else
      %{
        "logic" => params["start_conditions_logic"] || "and",
        "conditions" => Enum.reverse(conditions)
      }
    end
  end

  defp is_enabled?("true"), do: true
  defp is_enabled?(true), do: true
  defp is_enabled?("on"), do: true
  defp is_enabled?(_), do: false

  defp build_stop_conditions(params) do
    conditions = []

    # Take profit
    conditions =
      if is_enabled?(params["stop_tp_enabled"]) do
        tp_percent = parse_config_value(params["stop_tp_percent"]) || 5

        condition = %{
          "type" => "take_profit",
          "target_percent" => tp_percent
        }

        [condition | conditions]
      else
        conditions
      end

    # Stop loss
    conditions =
      if is_enabled?(params["stop_sl_enabled"]) do
        sl_percent = parse_config_value(params["stop_sl_percent"]) || 2

        condition = %{
          "type" => "stop_loss",
          "limit_percent" => sl_percent
        }

        [condition | conditions]
      else
        conditions
      end

    # Max daily loss
    conditions =
      if is_enabled?(params["stop_daily_enabled"]) do
        daily_limit = parse_config_value(params["stop_daily_limit"]) || 100

        condition = %{
          "type" => "max_daily_loss",
          "limit" => daily_limit
        }

        [condition | conditions]
      else
        conditions
      end

    # Time stop
    conditions =
      if is_enabled?(params["stop_time_enabled"]) do
        time_at = params["stop_time_at"] || "17:00"

        condition = %{
          "type" => "time_stop",
          "stop_at" => time_at,
          "timezone" => "UTC"
        }

        [condition | conditions]
      else
        conditions
      end

    if Enum.empty?(conditions) do
      nil
    else
      %{
        "logic" => params["stop_conditions_logic"] || "or",
        "conditions" => Enum.reverse(conditions)
      }
    end
  end

  defp maybe_add_conditions(config, _key, nil), do: config
  defp maybe_add_conditions(config, key, conditions), do: Map.put(config, key, conditions)

  defp activate_strategy(strategy_id) do
    case Repo.get(Setting, strategy_id) do
      nil ->
        {:error, "Strategy not found"}

      strategy ->
        # Use Ecto.Changeset.change to bypass validation when just changing is_active
        strategy
        |> Ecto.Changeset.change(%{is_active: true})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            # Notify the trading engine to start the strategy
            Phoenix.PubSub.broadcast(
              BinanceSystem.PubSub,
              "strategy_updates",
              {:strategy_activated, updated}
            )

            {:ok, updated}

          {:error, changeset} ->
            {:error, format_changeset_errors(changeset)}
        end
    end
  end

  defp deactivate_strategy(strategy_id) do
    case Repo.get(Setting, strategy_id) do
      nil ->
        {:error, "Strategy not found"}

      strategy ->
        # Use Ecto.Changeset.change to bypass validation when just changing is_active
        strategy
        |> Ecto.Changeset.change(%{is_active: false})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            # Notify the trading engine to stop the strategy
            Phoenix.PubSub.broadcast(
              BinanceSystem.PubSub,
              "strategy_updates",
              {:strategy_deactivated, updated}
            )

            {:ok, updated}

          {:error, changeset} ->
            {:error, format_changeset_errors(changeset)}
        end
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-base-content">Trading Strategies</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Configure and manage automated trading strategies
        </p>
      </div>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body pb-0">
          <h2 class="card-title">Strategies</h2>
        </div>
        <div class="p-6">
          <%!-- Strategy Form --%>
          <%= if @show_strategy_form do %>
            <div class="card bg-base-200 mb-6">
              <div class="card-body">
                <h3 class="card-title">
                  {if @editing_strategy, do: "Edit", else: "Configure"} Strategy: {String.capitalize(
                    @selected_strategy_type || ""
                  )}
                </h3>
                <.form for={@strategy_form} phx-change="validate_strategy" phx-submit="save_strategy">
                  <div class="space-y-4">
                    <input
                      type="hidden"
                      name="setting[strategy_name]"
                      value={@selected_strategy_type}
                    />

                    <div class="form-control">
                      <label class="label">
                        <span class="label-text">Account</span>
                      </label>
                      <select name="setting[account_id]" class="select w-full">
                        <option value="">Select account...</option>
                        <%= for account <- @accounts do %>
                          <option
                            value={account.id}
                            selected={@strategy_form[:account_id].value == account.id}
                          >
                            {account.label}
                          </option>
                        <% end %>
                      </select>
                      <%= if @strategy_form[:account_id].errors != [] do %>
                        <label class="label">
                          <span class="label-text-alt text-error">
                            {translate_error(@strategy_form[:account_id].errors)}
                          </span>
                        </label>
                      <% end %>
                      <%= if Enum.empty?(@accounts) do %>
                        <label class="label">
                          <span class="label-text-alt text-warning">
                            No accounts available. Please create an account in the Settings page first.
                          </span>
                        </label>
                      <% end %>
                    </div>
                    <%!-- Symbol Selector --%>
                    <div class="form-control">
                      <label class="label">
                        <span class="label-text">Trading Symbol</span>
                      </label>
                      <select name="setting[config_symbol]" class="select w-full">
                        <%= for symbol <- Settings.available_symbols() do %>
                          <option
                            value={symbol}
                            selected={get_config_value(@strategy_form, "symbol", "BTCUSDT") == symbol}
                          >
                            {symbol}
                          </option>
                        <% end %>
                      </select>
                      <label class="label">
                        <span class="label-text-alt">Select the cryptocurrency pair to trade</span>
                      </label>
                    </div>
                    <%!-- Strategy-specific config fields --%>
                    <div class="divider">Configuration</div>

                    <%= case @selected_strategy_type do %>
                      <% "naive" -> %>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Buy Threshold (%)</span>
                            </label>
                            <input
                              type="number"
                              step="0.001"
                              name="setting[config_buy_threshold]"
                              value={get_config_value(@strategy_form, "buy_threshold", -0.01)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">Price drop to trigger buy</span>
                            </label>
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Sell Threshold (%)</span>
                            </label>
                            <input
                              type="number"
                              step="0.001"
                              name="setting[config_sell_threshold]"
                              value={get_config_value(@strategy_form, "sell_threshold", 0.01)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">Price rise to trigger sell</span>
                            </label>
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Trade Amount (USDT)</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_trade_amount]"
                              value={get_config_value(@strategy_form, "trade_amount", 100)}
                              class="input"
                            />
                          </div>
                        </div>
                      <% "grid" -> %>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Grid Levels</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_grid_levels]"
                              value={get_config_value(@strategy_form, "grid_levels", 10)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">Number of price levels</span>
                            </label>
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Grid Spacing (%)</span>
                            </label>
                            <input
                              type="number"
                              step="0.001"
                              name="setting[config_grid_spacing]"
                              value={get_config_value(@strategy_form, "grid_spacing", 0.01)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">% between levels</span>
                            </label>
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Amount per Grid (USDT)</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_amount_per_grid]"
                              value={get_config_value(@strategy_form, "amount_per_grid", 50)}
                              class="input"
                            />
                          </div>
                        </div>
                      <% "dca" -> %>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Interval (hours)</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_interval_hours]"
                              value={get_config_value(@strategy_form, "interval_hours", 24)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">Hours between buys</span>
                            </label>
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Amount per Buy (USDT)</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_amount_per_buy]"
                              value={get_config_value(@strategy_form, "amount_per_buy", 100)}
                              class="input"
                            />
                          </div>
                          <div class="form-control">
                            <label class="label">
                              <span class="label-text">Max Buys</span>
                            </label>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_max_buys]"
                              value={get_config_value(@strategy_form, "max_buys", 30)}
                              class="input"
                            />
                            <label class="label">
                              <span class="label-text-alt">Total number of purchases</span>
                            </label>
                          </div>
                        </div>
                      <% _ -> %>
                        <p class="text-base-content/70">Select a strategy type to configure.</p>
                    <% end %>
                    <%!-- Start Conditions Section --%>
                    <div class="collapse collapse-arrow bg-base-100 border border-base-300 mt-4">
                      <input type="checkbox" name="start_conditions_toggle" />
                      <div class="collapse-title font-medium">
                        Start Conditions (Optional)
                      </div>
                      <div class="collapse-content">
                        <p class="text-sm text-base-content/70 mb-4">
                          Strategy will wait for these conditions before starting to trade.
                        </p>

                        <div class="form-control mb-4">
                          <label class="label">
                            <span class="label-text">Condition Logic</span>
                          </label>
                          <select
                            name="setting[config_start_conditions_logic]"
                            class="select select-sm w-full max-w-xs"
                          >
                            <option
                              value="and"
                              selected={
                                get_nested_config(
                                  @strategy_form,
                                  ["start_conditions", "logic"],
                                  "and"
                                ) == "and"
                              }
                            >
                              ALL conditions (AND)
                            </option>
                            <option
                              value="or"
                              selected={
                                get_nested_config(
                                  @strategy_form,
                                  ["start_conditions", "logic"],
                                  "and"
                                ) == "or"
                              }
                            >
                              ANY condition (OR)
                            </option>
                          </select>
                        </div>
                        <%!-- Price Condition --%>
                        <div class="form-control mb-3">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="hidden"
                              name="setting[config_start_price_enabled]"
                              value="false"
                            />
                            <input
                              type="checkbox"
                              name="setting[config_start_price_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "start_conditions", "price")
                              }
                              class="checkbox checkbox-sm"
                            />
                            <span class="label-text">Price Condition</span>
                          </label>
                          <div class="flex gap-2 ml-8">
                            <select
                              name="setting[config_start_price_op]"
                              class="select select-sm"
                            >
                              <option
                                value="below"
                                selected={
                                  get_condition_field(
                                    @strategy_form,
                                    "start_conditions",
                                    "price",
                                    "operator",
                                    "below"
                                  ) == "below"
                                }
                              >
                                Below
                              </option>
                              <option
                                value="above"
                                selected={
                                  get_condition_field(
                                    @strategy_form,
                                    "start_conditions",
                                    "price",
                                    "operator",
                                    "below"
                                  ) == "above"
                                }
                              >
                                Above
                              </option>
                            </select>
                            <input
                              type="number"
                              step="0.01"
                              name="setting[config_start_price_value]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "start_conditions",
                                  "price",
                                  "value",
                                  ""
                                )
                              }
                              placeholder="Price"
                              class="input input-sm w-32"
                            />
                            <span class="self-center text-sm">USDT</span>
                          </div>
                        </div>
                        <%!-- Time Condition --%>
                        <div class="form-control mb-3">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="hidden"
                              name="setting[config_start_time_enabled]"
                              value="false"
                            />
                            <input
                              type="checkbox"
                              name="setting[config_start_time_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "start_conditions", "time")
                              }
                              class="checkbox checkbox-sm"
                            />
                            <span class="label-text">Time Window</span>
                          </label>
                          <div class="flex gap-2 ml-8 items-center">
                            <span class="text-sm">From</span>
                            <input
                              type="number"
                              min="0"
                              max="23"
                              name="setting[config_start_time_from]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "start_conditions",
                                  "time",
                                  "start_hour",
                                  9
                                )
                              }
                              class="input input-sm w-16"
                            />
                            <span class="text-sm">to</span>
                            <input
                              type="number"
                              min="0"
                              max="23"
                              name="setting[config_start_time_to]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "start_conditions",
                                  "time",
                                  "end_hour",
                                  17
                                )
                              }
                              class="input input-sm w-16"
                            />
                            <span class="text-sm">UTC</span>
                          </div>
                        </div>
                        <%!-- Volume Condition --%>
                        <div class="form-control">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="hidden"
                              name="setting[config_start_volume_enabled]"
                              value="false"
                            />
                            <input
                              type="checkbox"
                              name="setting[config_start_volume_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "start_conditions", "volume")
                              }
                              class="checkbox checkbox-sm"
                            />
                            <span class="label-text">Volume Condition (24h)</span>
                          </label>
                          <div class="flex gap-2 ml-8">
                            <select
                              name="setting[config_start_volume_op]"
                              class="select select-sm"
                            >
                              <option
                                value="above"
                                selected={
                                  get_condition_field(
                                    @strategy_form,
                                    "start_conditions",
                                    "volume",
                                    "operator",
                                    "above"
                                  ) == "above"
                                }
                              >
                                Above
                              </option>
                              <option
                                value="below"
                                selected={
                                  get_condition_field(
                                    @strategy_form,
                                    "start_conditions",
                                    "volume",
                                    "operator",
                                    "above"
                                  ) == "below"
                                }
                              >
                                Below
                              </option>
                            </select>
                            <input
                              type="number"
                              step="1"
                              name="setting[config_start_volume_value]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "start_conditions",
                                  "volume",
                                  "value",
                                  ""
                                )
                              }
                              placeholder="Volume"
                              class="input input-sm w-32"
                            />
                            <span class="self-center text-sm">USDT</span>
                          </div>
                        </div>
                      </div>
                    </div>
                    <%!-- Stop Conditions Section --%>
                    <div class="collapse collapse-arrow bg-base-100 border border-base-300 mt-2">
                      <input type="checkbox" name="stop_conditions_toggle" />
                      <div class="collapse-title font-medium">
                        Stop Conditions (Optional)
                      </div>
                      <div class="collapse-content">
                        <p class="text-sm text-base-content/70 mb-4">
                          Strategy will automatically stop when these conditions are met.
                        </p>

                        <div class="form-control mb-4">
                          <label class="label">
                            <span class="label-text">Condition Logic</span>
                          </label>
                          <select
                            name="setting[config_stop_conditions_logic]"
                            class="select select-sm w-full max-w-xs"
                          >
                            <option
                              value="or"
                              selected={
                                get_nested_config(@strategy_form, ["stop_conditions", "logic"], "or") ==
                                  "or"
                              }
                            >
                              ANY condition (OR) - Stop on first match
                            </option>
                            <option
                              value="and"
                              selected={
                                get_nested_config(@strategy_form, ["stop_conditions", "logic"], "or") ==
                                  "and"
                              }
                            >
                              ALL conditions (AND)
                            </option>
                          </select>
                        </div>
                        <%!-- Take Profit --%>
                        <div class="form-control mb-3">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input type="hidden" name="setting[config_stop_tp_enabled]" value="false" />
                            <input
                              type="checkbox"
                              name="setting[config_stop_tp_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "stop_conditions", "take_profit")
                              }
                              class="checkbox checkbox-sm checkbox-success"
                            />
                            <span class="label-text text-success">Take Profit</span>
                          </label>
                          <div class="flex gap-2 ml-8">
                            <input
                              type="number"
                              step="0.1"
                              name="setting[config_stop_tp_percent]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "stop_conditions",
                                  "take_profit",
                                  "target_percent",
                                  5
                                )
                              }
                              placeholder="%"
                              class="input input-sm w-20"
                            />
                            <span class="self-center text-sm">% profit</span>
                          </div>
                        </div>
                        <%!-- Stop Loss --%>
                        <div class="form-control mb-3">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input type="hidden" name="setting[config_stop_sl_enabled]" value="false" />
                            <input
                              type="checkbox"
                              name="setting[config_stop_sl_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "stop_conditions", "stop_loss")
                              }
                              class="checkbox checkbox-sm checkbox-error"
                            />
                            <span class="label-text text-error">Stop Loss</span>
                          </label>
                          <div class="flex gap-2 ml-8">
                            <input
                              type="number"
                              step="0.1"
                              name="setting[config_stop_sl_percent]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "stop_conditions",
                                  "stop_loss",
                                  "limit_percent",
                                  2
                                )
                              }
                              placeholder="%"
                              class="input input-sm w-20"
                            />
                            <span class="self-center text-sm">% loss</span>
                          </div>
                        </div>
                        <%!-- Max Daily Loss --%>
                        <div class="form-control mb-3">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="hidden"
                              name="setting[config_stop_daily_enabled]"
                              value="false"
                            />
                            <input
                              type="checkbox"
                              name="setting[config_stop_daily_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(
                                  @strategy_form,
                                  "stop_conditions",
                                  "max_daily_loss"
                                )
                              }
                              class="checkbox checkbox-sm checkbox-warning"
                            />
                            <span class="label-text text-warning">Max Daily Loss</span>
                          </label>
                          <div class="flex gap-2 ml-8">
                            <input
                              type="number"
                              step="1"
                              name="setting[config_stop_daily_limit]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "stop_conditions",
                                  "max_daily_loss",
                                  "limit",
                                  100
                                )
                              }
                              placeholder="Amount"
                              class="input input-sm w-24"
                            />
                            <span class="self-center text-sm">USDT</span>
                          </div>
                        </div>
                        <%!-- Time Stop --%>
                        <div class="form-control">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="hidden"
                              name="setting[config_stop_time_enabled]"
                              value="false"
                            />
                            <input
                              type="checkbox"
                              name="setting[config_stop_time_enabled]"
                              value="true"
                              checked={
                                has_condition_type?(@strategy_form, "stop_conditions", "time_stop")
                              }
                              class="checkbox checkbox-sm"
                            />
                            <span class="label-text">Time Stop</span>
                          </label>
                          <div class="flex gap-2 ml-8 items-center">
                            <span class="text-sm">Stop at</span>
                            <input
                              type="text"
                              name="setting[config_stop_time_at]"
                              value={
                                get_condition_field(
                                  @strategy_form,
                                  "stop_conditions",
                                  "time_stop",
                                  "stop_at",
                                  "17:00"
                                )
                              }
                              placeholder="HH:MM"
                              class="input input-sm w-20"
                            />
                            <span class="text-sm">UTC</span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div class="form-control mt-4">
                      <label class="label cursor-pointer justify-start gap-2">
                        <input type="hidden" name="setting[is_active]" value="false" />
                        <input
                          type="checkbox"
                          name="setting[is_active]"
                          value="true"
                          checked={
                            @strategy_form[:is_active].value == true ||
                              @strategy_form[:is_active].value == "true"
                          }
                          class="checkbox checkbox-primary"
                        />
                        <span class="label-text">Start immediately</span>
                      </label>
                    </div>

                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary" disabled={Enum.empty?(@accounts)}>
                        {if @editing_strategy, do: "Update", else: "Create"} Strategy
                      </button>
                      <button type="button" phx-click="hide_strategy_form" class="btn btn-ghost">
                        Cancel
                      </button>
                    </div>
                  </div>
                </.form>
              </div>
            </div>
          <% end %>
          <%!-- Available Strategy Types --%>
          <%= if !@show_strategy_form do %>
            <h3 class="text-lg font-medium text-base-content mb-4">Available Strategies</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <%= for strategy_type <- @available_strategies do %>
                <div class="card bg-base-100 border border-base-300">
                  <div class="card-body">
                    <h3 class="card-title">{strategy_type.label}</h3>
                    <p class="text-base-content/70">
                      {strategy_type.description}
                    </p>
                    <div class="card-actions justify-end mt-4">
                      <button
                        phx-click="select_strategy_type"
                        phx-value-type={strategy_type.name}
                        class="btn btn-primary btn-block"
                      >
                        Configure
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
          <%!-- Configured Strategies List --%>
          <%= if !Enum.empty?(@strategies) do %>
            <div class="mt-8">
              <h3 class="text-lg font-medium text-base-content mb-4">Your Strategies</h3>
              <div class="space-y-4">
                <%= for strategy <- @strategies do %>
                  <div class="card bg-base-100 border border-base-300">
                    <div class="card-body">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <div class="flex items-center gap-2">
                            <h4 class="font-medium text-base-content text-lg">
                              {String.capitalize(strategy.strategy_name)}
                            </h4>
                            <%= if Map.has_key?(@running_strategies, strategy.id) do %>
                              <span class="badge badge-success">
                                <span class="animate-pulse mr-1">●</span> Running
                              </span>
                            <% else %>
                              <%= if strategy.is_active do %>
                                <span class="badge badge-warning">
                                  <span class="animate-pulse mr-1">●</span> Starting...
                                </span>
                              <% else %>
                                <span class="badge badge-ghost">
                                  Stopped
                                </span>
                              <% end %>
                            <% end %>
                          </div>
                          <div class="mt-2 space-y-1">
                            <%= if strategy.account do %>
                              <p class="text-sm text-base-content/70">
                                <span class="font-medium">Account:</span> {strategy.account.label}
                              </p>
                            <% end %>
                            <div class="text-sm text-base-content/70">
                              <span class="font-medium">Config:</span>
                              <span class="font-mono text-xs">
                                {inspect(strategy.config, pretty: true, limit: 50)}
                              </span>
                            </div>
                          </div>
                        </div>
                        <div class="flex flex-col gap-2">
                          <%= if strategy.is_active do %>
                            <button
                              phx-click="deactivate_strategy"
                              phx-value-id={strategy.id}
                              class="btn btn-sm btn-error"
                            >
                              Stop
                            </button>
                          <% else %>
                            <button
                              phx-click="activate_strategy"
                              phx-value-id={strategy.id}
                              class="btn btn-sm btn-success"
                            >
                              Start
                            </button>
                          <% end %>
                          <button
                            phx-click="edit_strategy"
                            phx-value-id={strategy.id}
                            class="btn btn-sm btn-ghost"
                          >
                            Edit
                          </button>
                          <button
                            phx-click="delete_strategy"
                            phx-value-id={strategy.id}
                            data-confirm="Are you sure you want to delete this strategy?"
                            class="btn btn-sm btn-ghost text-error"
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_data(socket) do
    # TODO: Link PhoenixKit users to SharedData accounts
    # For now, load all accounts without user filtering
    socket
    |> assign(accounts: load_accounts(nil))
    |> assign(strategies: load_strategies(nil))
  end

  defp sync_running_strategies(socket) do
    # Query TraderRegistry to get actual running strategies
    running_strategies =
      socket.assigns.strategies
      |> Enum.reduce(%{}, fn strategy, acc ->
        case Registry.lookup(TradingEngine.TraderRegistry, strategy.id) do
          [{_pid, _}] ->
            # Trader process exists - mark as running
            Map.put(acc, strategy.id, true)

          [] ->
            # No Trader process found
            acc
        end
      end)

    assign(socket, running_strategies: running_strategies)
  end

  defp load_accounts(user_id) do
    Accounts.list_user_accounts(user_id)
  end

  defp load_strategies(user_id) do
    Settings.list_user_strategies(user_id)
  end

  defp get_config_value(form, key, default) do
    case form[:config].value do
      nil -> default
      config when is_map(config) -> Map.get(config, key, default)
      _ -> default
    end
  end

  defp get_nested_config(form, path, default) when is_list(path) do
    case form[:config].value do
      nil ->
        default

      config when is_map(config) ->
        get_in(config, path) || default

      _ ->
        default
    end
  end

  # Check if a condition type is enabled by looking at the conditions array
  defp has_condition_type?(form, conditions_key, condition_type) do
    case form[:config].value do
      nil ->
        false

      config when is_map(config) ->
        case get_in(config, [conditions_key, "conditions"]) do
          nil ->
            false

          conditions when is_list(conditions) ->
            Enum.any?(conditions, fn c -> c["type"] == condition_type end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  # Get a specific field from a condition type
  defp get_condition_field(form, conditions_key, condition_type, field, default) do
    case form[:config].value do
      nil ->
        default

      config when is_map(config) ->
        case get_in(config, [conditions_key, "conditions"]) do
          nil ->
            default

          conditions when is_list(conditions) ->
            case Enum.find(conditions, fn c -> c["type"] == condition_type end) do
              nil -> default
              condition -> Map.get(condition, field, default)
            end

          _ ->
            default
        end

      _ ->
        default
    end
  end

  defp translate_error(errors) when is_list(errors) do
    errors
    |> Enum.map(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.join(", ")
  end
end
