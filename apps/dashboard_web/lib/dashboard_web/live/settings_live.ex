defmodule DashboardWeb.SettingsLive do
  use DashboardWeb, :live_view

  alias SharedData.Repo
  alias SharedData.Schemas.{Account, ApiCredential}
  alias SharedData.{Accounts, Credentials}
  alias SharedData.Helpers.CredentialHelper
  alias DashboardWeb.Forms.AccountForm
  alias DashboardWeb.Live.UserContext

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> UserContext.assign_user_context()
      |> assign(page_title: "Trading Accounts")
      |> assign(current_path: "/app/accounts")
      |> assign(accounts: [])
      # Account form state (includes API credentials)
      |> assign(show_account_form: false)
      |> assign(editing_account: nil)
      |> assign(account_form: nil)
      |> assign(test_result: nil)
      |> load_data()

    {:ok, socket}
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


  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold text-base-content">Settings</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Manage your trading accounts and API credentials
        </p>
      </div>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body pb-0 flex-row justify-between items-center">
            <h2 class="card-title">Trading Accounts</h2>
            <button
              :if={!@show_account_form}
              phx-click="show_account_form"
              class="btn btn-primary"
            >
              Add Account
            </button>
          </div>
          <div class="p-6">
            <%!-- Security Notice --%>
            <div class="alert alert-warning mb-6">
              <span class={["hero-exclamation-triangle", "stroke-current shrink-0 h-6 w-6"]} />
              <div>
                <div class="font-bold">Security Notice</div>
                <div class="text-sm">Your API keys are encrypted in the database. Never share your API keys with anyone.</div>
              </div>
            </div>

            <%!-- Add/Edit Account Form --%>
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
                          class="input w-full"
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
                          class="input w-full font-mono"
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
                          class="input w-full font-mono"
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
                          class="input w-full"
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

            <%!-- Test Result --%>
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

            <%!-- Accounts List --%>
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

    </div>
    """
  end

  defp load_data(socket) do
    # Phase 8: Will load data based on authenticated user
    user_id = socket.assigns.user_id

    socket
    |> assign(accounts: load_accounts(user_id))
  end

  defp load_accounts(user_id) do
    Accounts.list_user_accounts(user_id)
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

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
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
end
