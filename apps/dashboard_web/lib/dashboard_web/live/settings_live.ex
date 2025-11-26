defmodule DashboardWeb.SettingsLive do
  use DashboardWeb, :live_view

  alias SharedData.Repo
  alias SharedData.Schemas.{Account, Setting, ApiCredential}
  alias SharedData.{Accounts, Credentials, Settings}
  alias SharedData.Helpers.CredentialHelper
  alias DashboardWeb.Forms.AccountForm

  @impl true
  def mount(_params, _session, socket) do
    # Phase 8: Will get user_id from authenticated session
    socket =
      socket
      |> assign(page_title: "Settings")
      |> assign(current_path: "/settings")
      |> assign(accounts: [])
      |> assign(strategies: [])
      |> assign(selected_tab: "accounts")
      |> assign(user_id: nil)
      # Account form state (includes API credentials)
      |> assign(show_account_form: false)
      |> assign(editing_account: nil)
      |> assign(account_form: nil)
      |> assign(test_result: nil)
      # Strategy form state
      |> assign(show_strategy_form: false)
      |> assign(editing_strategy: nil)
      |> assign(strategy_form: nil)
      |> assign(selected_strategy_type: nil)
      |> assign(available_strategies: Settings.available_strategies())
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(selected_tab: tab)
      |> assign(show_account_form: false)
      |> assign(editing_account: nil)
      |> assign(test_result: nil)
      |> assign(show_strategy_form: false)
      |> assign(editing_strategy: nil)
      |> assign(selected_strategy_type: nil)

    {:noreply, socket}
  end

  # ==================== Account Events (with embedded API credentials) ====================

  @impl true
  def handle_event("show_account_form", _params, socket) do
    changeset = AccountForm.changeset(AccountForm.new())

    socket =
      socket
      |> assign(show_account_form: true)
      |> assign(editing_account: nil)
      |> assign(account_form: to_form(changeset, as: "account"))
      |> assign(test_result: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_account_form", _params, socket) do
    socket =
      socket
      |> assign(show_account_form: false)
      |> assign(editing_account: nil)
      |> assign(account_form: nil)
      |> assign(test_result: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_account", %{"id" => account_id}, socket) do
    case Accounts.get_account_by_user(account_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        form_data = AccountForm.from_account(account)
        changeset = AccountForm.changeset_for_edit(form_data)

        socket =
          socket
          |> assign(show_account_form: true)
          |> assign(editing_account: account)
          |> assign(account_form: to_form(changeset, as: "account"))
          |> assign(test_result: nil)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_account", %{"account" => params}, socket) do
    changeset =
      case socket.assigns.editing_account do
        nil ->
          AccountForm.new()
          |> AccountForm.changeset(params)
          |> Map.put(:action, :validate)

        _account ->
          AccountForm.new()
          |> AccountForm.changeset_for_edit(params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign(socket, account_form: to_form(changeset, as: "account"))}
  end

  @impl true
  def handle_event("save_account", %{"account" => params}, socket) do
    user_id = socket.assigns.user_id

    case socket.assigns.editing_account do
      nil ->
        # Create new account with API credentials
        create_account_with_credentials(socket, params, user_id)

      account ->
        # Update existing account
        update_account_with_credentials(socket, account, params, user_id)
    end
  end

  defp create_account_with_credentials(socket, params, user_id) do
    # First validate with AccountForm
    changeset = AccountForm.changeset(AccountForm.new(), params)

    # Debug
    IO.inspect(changeset, label: "CHANGESET")
    IO.inspect(changeset.valid?, label: "VALID?")
    IO.inspect(changeset.errors, label: "ERRORS")

    if changeset.valid? do
      # Extract credential params
      credential_params = %{
        "label" => params["label"],
        "api_key" => params["api_key"],
        "secret_key" => params["secret_key"],
        "is_testnet" => params["is_testnet"] == "on" || params["is_testnet"] == true,
        "is_active" => true,
        "user_id" => user_id
      }

      # Use Ecto.Multi for transaction
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:credential, fn _changes ->
          Credentials.change_credential(%ApiCredential{}, credential_params)
        end)
        |> Ecto.Multi.insert(:account, fn %{credential: credential} ->
          account_params = %{
            "label" => params["label"],
            "binance_account_id" => params["binance_account_id"],
            "is_active" => true,
            "user_id" => user_id,
            "api_credential_id" => credential.id
          }

          Accounts.change_account(%Account{}, account_params)
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{account: _account}} ->
          socket =
            socket
            |> put_flash(:info, "Account created successfully")
            |> assign(show_account_form: false)
            |> assign(account_form: nil)
            |> assign(test_result: nil)
            |> load_data()

          {:noreply, socket}

        {:error, :credential, db_changeset, _changes} ->
          # Convert DB errors to form errors
          socket =
            socket
            |> put_flash(:error, "Failed to save API credentials: #{format_errors(db_changeset)}")
            |> assign(account_form: to_form(Map.put(changeset, :action, :insert), as: "account"))

          {:noreply, socket}

        {:error, :account, db_changeset, _changes} ->
          socket =
            socket
            |> put_flash(:error, "Failed to create account: #{format_errors(db_changeset)}")
            |> assign(account_form: to_form(Map.put(changeset, :action, :insert), as: "account"))

          {:noreply, socket}
      end
    else
      socket =
        socket
        |> assign(account_form: to_form(Map.put(changeset, :action, :insert), as: "account"))

      {:noreply, socket}
    end
  end

  defp update_account_with_credentials(socket, account, params, _user_id) do
    # Validate with AccountForm for edit
    changeset = AccountForm.changeset_for_edit(AccountForm.new(), params)

    if changeset.valid? do
      # Update account basic info
      account_params = %{
        "label" => params["label"],
        "binance_account_id" => params["binance_account_id"],
        "is_active" => params["is_active"] == "on" || params["is_active"] == true
      }

      # Update credentials if provided
      credential_updates =
        if params["api_key"] && params["api_key"] != "" do
          %{
            "api_key" => params["api_key"],
            "secret_key" => params["secret_key"],
            "is_testnet" => params["is_testnet"] == "on" || params["is_testnet"] == true
          }
        else
          %{"is_testnet" => params["is_testnet"] == "on" || params["is_testnet"] == true}
        end

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.update(:account, Accounts.change_account(account, account_params))
        |> Ecto.Multi.update(:credential, fn _changes ->
          Credentials.change_credential(account.api_credential, credential_updates)
        end)
        |> Repo.transaction()

      case result do
        {:ok, _changes} ->
          socket =
            socket
            |> put_flash(:info, "Account updated successfully")
            |> assign(show_account_form: false)
            |> assign(editing_account: nil)
            |> assign(account_form: nil)
            |> assign(test_result: nil)
            |> load_data()

          {:noreply, socket}

        {:error, _step, db_changeset, _changes} ->
          socket =
            socket
            |> put_flash(:error, "Failed to update: #{format_errors(db_changeset)}")
            |> assign(account_form: to_form(Map.put(changeset, :action, :update), as: "account"))

          {:noreply, socket}
      end
    else
      socket =
        socket
        |> assign(account_form: to_form(Map.put(changeset, :action, :update), as: "account"))

      {:noreply, socket}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def handle_event("delete_account", %{"id" => account_id}, socket) do
    case Accounts.get_account_by_user(account_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        # Delete account and its credential in a transaction
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.delete(:account, account)
          |> Ecto.Multi.run(:credential, fn _repo, _changes ->
            if account.api_credential do
              Credentials.delete_credential(account.api_credential)
            else
              {:ok, nil}
            end
          end)
          |> Repo.transaction()

        case result do
          {:ok, _changes} ->
            socket =
              socket
              |> put_flash(:info, "Account deleted successfully")
              |> load_data()

            {:noreply, socket}

          {:error, _step, _changeset, _changes} ->
            {:noreply, put_flash(socket, :error, "Failed to delete account")}
        end
    end
  end

  @impl true
  def handle_event("toggle_account_active", %{"id" => account_id}, socket) do
    case Accounts.get_account_by_user(account_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        new_status = !account.is_active

        case Accounts.update_account(account, %{is_active: new_status}) do
          {:ok, _account} ->
            status_msg = if new_status, do: "activated", else: "deactivated"

            socket =
              socket
              |> put_flash(:info, "Account #{status_msg} successfully")
              |> load_data()

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update account")}
        end
    end
  end

  @impl true
  def handle_event("test_account", %{"id" => account_id}, socket) do
    case Accounts.get_account_by_user(account_id, socket.assigns.user_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Account not found")}

      account ->
        case Credentials.test_credential(account.api_credential) do
          {:ok, account_info} ->
            result = %{
              success: true,
              message: "Connection successful!",
              account_type: Map.get(account_info, "accountType", "N/A"),
              can_trade: Map.get(account_info, "canTrade", false)
            }

            socket =
              socket
              |> put_flash(:info, "Connection test successful")
              |> assign(test_result: result)

            {:noreply, socket}

          {:error, reason} ->
            result = %{
              success: false,
              message: "Connection failed: #{inspect(reason)}"
            }

            socket =
              socket
              |> put_flash(:error, "Connection test failed")
              |> assign(test_result: result)

            {:noreply, socket}
        end
    end
  end

  # ==================== Strategy Events ====================

  @impl true
  def handle_event("activate_strategy", %{"id" => strategy_id}, socket) do
    case activate_strategy(strategy_id) do
      {:ok, _strategy} ->
        socket =
          socket
          |> put_flash(:info, "Strategy activated successfully")
          |> load_data()

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
          {:ok, _setting} ->
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
        case Settings.update_setting(strategy, params) do
          {:ok, _setting} ->
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

  defp parse_strategy_config(params) do
    # Convert config fields to a map
    config =
      params
      |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "config_") end)
      |> Enum.map(fn {k, v} ->
        key = String.replace_prefix(k, "config_", "")
        # Try to parse as number if possible
        value =
          case Float.parse(v) do
            {num, ""} -> num
            _ ->
              case Integer.parse(v) do
                {num, ""} -> num
                _ -> v
              end
          end

        {key, value}
      end)
      |> Enum.into(%{})

    params
    |> Map.drop(Enum.map(Map.keys(config), fn k -> "config_#{k}" end))
    |> Map.put("config", config)
  end

  defp activate_strategy(strategy_id) do
    case Repo.get(Setting, strategy_id) do
      nil ->
        {:error, "Strategy not found"}

      strategy ->
        strategy
        |> Setting.changeset(%{is_active: true})
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

          error ->
            error
        end
    end
  end

  defp deactivate_strategy(strategy_id) do
    case Repo.get(Setting, strategy_id) do
      nil ->
        {:error, "Strategy not found"}

      strategy ->
        strategy
        |> Setting.changeset(%{is_active: false})
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

          error ->
            error
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-base-content">Settings</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Manage your accounts, API credentials, and trading strategies
        </p>
      </div>

      <!-- Tabs -->
      <div class="tabs tabs-bordered">
        <button
          phx-click="select_tab"
          phx-value-tab="accounts"
          class={["tab", @selected_tab == "accounts" && "tab-active"]}
        >
          Accounts
        </button>
        <button
          phx-click="select_tab"
          phx-value-tab="strategies"
          class={["tab", @selected_tab == "strategies" && "tab-active"]}
        >
          Strategies
        </button>
      </div>

      <!-- Accounts Tab -->
      <%= if @selected_tab == "accounts" do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="px-6 py-4 border-b border-base-300 flex justify-between items-center">
            <h2 class="text-xl font-semibold text-base-content">Trading Accounts</h2>
            <button
              :if={!@show_account_form}
              phx-click="show_account_form"
              class="btn btn-primary"
            >
              Add Account
            </button>
          </div>
          <div class="p-6">
            <!-- Security Notice -->
            <div class="alert alert-warning mb-6">
              <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <div>
                <div class="font-bold">Security Notice</div>
                <div class="text-sm">Your API keys are encrypted in the database. Never share your API keys with anyone.</div>
              </div>
            </div>

            <!-- Add/Edit Account Form -->
            <%= if @show_account_form do %>
              <div class="card bg-base-200 mb-6">
                <div class="card-body">
                  <h3 class="card-title">
                    <%= if @editing_account, do: "Edit", else: "Add" %> Trading Account
                  </h3>
                  <.form
                    for={@account_form}
                    phx-change="validate_account"
                    phx-submit="save_account"
                  >
                    <div class="space-y-4">
                      <div class="form-control">
                        <label class="label">
                          <span class="label-text">Account Name</span>
                        </label>
                        <input
                          type="text"
                          name="account[label]"
                          value={@account_form[:label].value}
                          placeholder="e.g., Main Trading, Testnet Account"
                          class="input input-bordered w-full"
                        />
                        <%= if @account_form[:label].errors != [] do %>
                          <label class="label">
                            <span class="label-text-alt text-error">
                              <%= translate_error(@account_form[:label].errors) %>
                            </span>
                          </label>
                        <% end %>
                      </div>

                      <div class="divider">API Credentials</div>

                      <div class="form-control">
                        <label class="label">
                          <span class="label-text">API Key</span>
                        </label>
                        <input
                          type="text"
                          name="account[api_key]"
                          value={@account_form[:api_key].value}
                          placeholder={if @editing_account, do: "Leave empty to keep current key", else: "Enter your Binance API key"}
                          class="input input-bordered w-full font-mono"
                        />
                        <%= if @account_form[:api_key].errors != [] do %>
                          <label class="label">
                            <span class="label-text-alt text-error">
                              <%= translate_error(@account_form[:api_key].errors) %>
                            </span>
                          </label>
                        <% end %>
                        <%= if @editing_account && @editing_account.api_credential do %>
                          <label class="label">
                            <span class="label-text-alt text-base-content/70">
                              Current: <%= CredentialHelper.mask_key(@editing_account.api_credential.api_key) %>
                            </span>
                          </label>
                        <% end %>
                      </div>

                      <div class="form-control">
                        <label class="label">
                          <span class="label-text">Secret Key</span>
                        </label>
                        <input
                          type="password"
                          name="account[secret_key]"
                          value={@account_form[:secret_key].value}
                          placeholder={if @editing_account, do: "Leave empty to keep current key", else: "Enter your Binance secret key"}
                          class="input input-bordered w-full font-mono"
                        />
                        <%= if @account_form[:secret_key].errors != [] do %>
                          <label class="label">
                            <span class="label-text-alt text-error">
                              <%= translate_error(@account_form[:secret_key].errors) %>
                            </span>
                          </label>
                        <% end %>
                        <%= if @editing_account && @editing_account.api_credential do %>
                          <label class="label">
                            <span class="label-text-alt text-base-content/70">
                              Current: <%= CredentialHelper.mask_key(@editing_account.api_credential.secret_key) %>
                            </span>
                          </label>
                        <% end %>
                      </div>

                      <div class="form-control">
                        <label class="label cursor-pointer justify-start gap-2">
                          <input
                            type="checkbox"
                            name="account[is_testnet]"
                            checked={@account_form[:is_testnet].value}
                            class="checkbox checkbox-primary"
                          />
                          <span class="label-text">Testnet Credentials</span>
                        </label>
                        <label class="label">
                          <span class="label-text-alt text-base-content/70">
                            Check this if these are Binance Testnet credentials
                          </span>
                        </label>
                      </div>

                      <div class="divider">Optional</div>

                      <div class="form-control">
                        <label class="label">
                          <span class="label-text">Binance Account ID (auto-detected)</span>
                        </label>
                        <input
                          type="text"
                          name="account[binance_account_id]"
                          value={@account_form[:binance_account_id].value}
                          placeholder="Will be auto-detected from API"
                          class="input input-bordered w-full"
                        />
                      </div>

                      <%= if @editing_account do %>
                        <div class="form-control">
                          <label class="label cursor-pointer justify-start gap-2">
                            <input
                              type="checkbox"
                              name="account[is_active]"
                              checked={@account_form[:is_active].value}
                              class="checkbox checkbox-primary"
                            />
                            <span class="label-text">Active</span>
                          </label>
                        </div>
                      <% end %>

                      <div class="flex gap-2 mt-6">
                        <button type="submit" class="btn btn-primary">
                          <%= if @editing_account, do: "Update Account", else: "Create Account" %>
                        </button>
                        <button
                          type="button"
                          phx-click="hide_account_form"
                          class="btn btn-ghost"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              </div>
            <% end %>

            <!-- Test Result -->
            <%= if @test_result do %>
              <div class={["alert mb-6", if(@test_result.success, do: "alert-success", else: "alert-error")]}>
                <div>
                  <div class="font-bold"><%= @test_result.message %></div>
                  <%= if @test_result.success do %>
                    <div class="text-sm">
                      Account Type: <%= @test_result.account_type %> |
                      Can Trade: <%= if @test_result.can_trade, do: "Yes", else: "No" %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Accounts List -->
            <%= if Enum.empty?(@accounts) and !@show_account_form do %>
              <div class="text-center text-base-content/70 py-8">
                No accounts configured. Add your first trading account to start.
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for account <- @accounts do %>
                  <div class="card bg-base-100 border border-base-300">
                    <div class="card-body">
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <div class="flex items-center gap-2">
                            <h3 class="text-lg font-medium text-base-content">
                              <%= account.label %>
                            </h3>
                            <span class={[
                              "badge",
                              if(account.is_active, do: "badge-success", else: "badge-ghost")
                            ]}>
                              <%= if account.is_active, do: "Active", else: "Inactive" %>
                            </span>
                            <%= if account.api_credential && account.api_credential.is_testnet do %>
                              <span class="badge badge-warning">Testnet</span>
                            <% end %>
                          </div>
                          <div class="mt-2 space-y-1">
                            <%= if account.api_credential do %>
                              <p class="text-sm text-base-content/70 font-mono">
                                <span class="font-sans font-medium">API Key:</span>
                                <%= CredentialHelper.mask_key(account.api_credential.api_key) %>
                              </p>
                            <% end %>
                            <%= if account.binance_account_id do %>
                              <p class="text-sm text-base-content/70">
                                <span class="font-medium">Binance ID:</span> <%= account.binance_account_id %>
                              </p>
                            <% end %>
                            <p class="text-xs text-base-content/50">
                              Updated <%= format_timestamp(account.updated_at) %>
                            </p>
                          </div>
                        </div>
                        <div class="flex flex-col gap-2">
                          <button
                            phx-click="test_account"
                            phx-value-id={account.id}
                            class="btn btn-sm btn-info"
                          >
                            Test Connection
                          </button>
                          <button
                            phx-click="toggle_account_active"
                            phx-value-id={account.id}
                            class={["btn btn-sm", if(account.is_active, do: "btn-warning", else: "btn-success")]}
                          >
                            <%= if account.is_active, do: "Deactivate", else: "Activate" %>
                          </button>
                          <button
                            phx-click="edit_account"
                            phx-value-id={account.id}
                            class="btn btn-sm btn-ghost"
                          >
                            Edit
                          </button>
                          <button
                            phx-click="delete_account"
                            phx-value-id={account.id}
                            data-confirm="Are you sure you want to delete this account and API credentials?"
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
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Strategies Tab -->
      <%= if @selected_tab == "strategies" do %>
        <div class="card bg-base-100 shadow-xl">
          <div class="px-6 py-4 border-b border-base-300">
            <h2 class="text-xl font-semibold text-base-content">Trading Strategies</h2>
          </div>
          <div class="p-6">
            <!-- Strategy Form -->
            <%= if @show_strategy_form do %>
              <div class="card bg-base-200 mb-6">
                <div class="card-body">
                  <h3 class="card-title">
                    <%= if @editing_strategy, do: "Edit", else: "Configure" %> Strategy: <%= String.capitalize(@selected_strategy_type || "") %>
                  </h3>
                  <.form
                    for={@strategy_form}
                    phx-change="validate_strategy"
                    phx-submit="save_strategy"
                  >
                    <div class="space-y-4">
                      <input type="hidden" name="setting[strategy_name]" value={@selected_strategy_type} />

                      <div class="form-control">
                        <label class="label">
                          <span class="label-text">Account</span>
                        </label>
                        <select
                          name="setting[account_id]"
                          class="select select-bordered w-full"
                        >
                          <option value="">Select account...</option>
                          <%= for account <- @accounts do %>
                            <option
                              value={account.id}
                              selected={@strategy_form[:account_id].value == account.id}
                            >
                              <%= account.label %>
                            </option>
                          <% end %>
                        </select>
                        <%= if @strategy_form[:account_id].errors != [] do %>
                          <label class="label">
                            <span class="label-text-alt text-error">
                              <%= translate_error(@strategy_form[:account_id].errors) %>
                            </span>
                          </label>
                        <% end %>
                        <%= if Enum.empty?(@accounts) do %>
                          <label class="label">
                            <span class="label-text-alt text-warning">
                              No accounts available. Please create an account in the Accounts tab first.
                            </span>
                          </label>
                        <% end %>
                      </div>

                      <!-- Strategy-specific config fields -->
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
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
                                class="input input-bordered"
                              />
                              <label class="label">
                                <span class="label-text-alt">Total number of purchases</span>
                              </label>
                            </div>
                          </div>

                        <% _ -> %>
                          <p class="text-base-content/70">Select a strategy type to configure.</p>
                      <% end %>

                      <div class="form-control">
                        <label class="label cursor-pointer justify-start gap-2">
                          <input
                            type="checkbox"
                            name="setting[is_active]"
                            checked={@strategy_form[:is_active].value == true}
                            class="checkbox checkbox-primary"
                          />
                          <span class="label-text">Start immediately</span>
                        </label>
                      </div>

                      <div class="flex gap-2">
                        <button type="submit" class="btn btn-primary" disabled={Enum.empty?(@accounts)}>
                          <%= if @editing_strategy, do: "Update", else: "Create" %> Strategy
                        </button>
                        <button
                          type="button"
                          phx-click="hide_strategy_form"
                          class="btn btn-ghost"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  </.form>
                </div>
              </div>
            <% end %>

            <!-- Available Strategy Types -->
            <%= if !@show_strategy_form do %>
              <h3 class="text-lg font-medium text-base-content mb-4">Available Strategies</h3>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                <%= for strategy_type <- @available_strategies do %>
                  <div class="card bg-base-100 border border-base-300">
                    <div class="card-body">
                      <h3 class="card-title"><%= strategy_type.label %></h3>
                      <p class="text-base-content/70">
                        <%= strategy_type.description %>
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

            <!-- Configured Strategies List -->
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
                                <%= String.capitalize(strategy.strategy_name) %>
                              </h4>
                              <span class={[
                                "badge",
                                if(strategy.is_active, do: "badge-success", else: "badge-ghost")
                              ]}>
                                <%= if strategy.is_active, do: "Running", else: "Stopped" %>
                              </span>
                            </div>
                            <div class="mt-2 space-y-1">
                              <%= if strategy.account do %>
                                <p class="text-sm text-base-content/70">
                                  <span class="font-medium">Account:</span> <%= strategy.account.label %>
                                </p>
                              <% end %>
                              <div class="text-sm text-base-content/70">
                                <span class="font-medium">Config:</span>
                                <span class="font-mono text-xs">
                                  <%= inspect(strategy.config, pretty: true, limit: 50) %>
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
      <% end %>

    </div>
    """
  end

  defp load_data(socket) do
    # Phase 8: Will load data based on authenticated user
    user_id = socket.assigns.user_id

    socket
    |> assign(accounts: load_accounts(user_id))
    |> assign(strategies: load_strategies(user_id))
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

  defp translate_error(errors) when is_list(errors) do
    errors
    |> Enum.map(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.join(", ")
  end

  defp format_timestamp(nil), do: "N/A"

  defp format_timestamp(timestamp) do
    case DateTime.from_naive(timestamp, "Etc/UTC") do
      {:ok, dt} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M")

      _ ->
        "N/A"
    end
  end
end
