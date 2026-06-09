defmodule DashboardWeb.Live.UserContext do
  @moduledoc """
  Helper module for extracting user context from LiveView socket.
  Provides functions to get user_id and account_id from PhoenixKit auth.
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Extracts user context from socket assigns and adds user_id to socket.
  Returns socket with :user_id and :account_id assigns.

  PhoenixKit's `phoenix_kit_ensure_authenticated` on_mount guarantees
  that phoenix_kit_current_user is present in authenticated routes.
  """
  def assign_user_context(socket) do
    # Single shared trading desk: all authenticated PhoenixKit users operate the
    # shared (unowned) account. We record the authenticated PhoenixKit user id
    # for audit/ownership checks instead of hardcoding nil (which fail-opened the
    # ownership guard). The desk account itself is the unowned account.
    user_id = get_user_id(socket)
    account_id = get_default_account_id(nil)

    socket
    |> assign(:user_id, user_id)
    |> assign(:account_id, account_id)
  end

  @doc """
  Gets the user ID from socket assigns.
  Returns nil if user is not authenticated.
  """
  def get_user_id(socket) do
    case socket.assigns[:phoenix_kit_current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  @doc """
  Gets the default account_id for a user.
  Returns the first active account or nil.
  """
  def get_default_account_id(nil) do
    # Fallback: get any account (for dev/test without user system)
    # Uses list_user_accounts with nil to get accounts without user_id
    case SharedData.Accounts.list_user_accounts(nil) do
      [account | _] -> account.id
      [] -> nil
    end
  end

  def get_default_account_id(user_id) do
    case SharedData.Accounts.list_user_accounts(user_id) do
      [account | _] -> account.id
      [] -> nil
    end
  end

  @doc """
  Validates that the user has access to the given account.

  Single shared desk policy: unowned (shared) accounts are accessible to any
  authenticated user; owned accounts only to their owner. There is no longer a
  blanket fail-open when `user_id` is nil.
  """
  def user_owns_account?(_socket, nil), do: false

  def user_owns_account?(socket, account_id) do
    user_id = socket.assigns[:user_id]

    try do
      account = SharedData.Accounts.get_account!(account_id)
      is_nil(account.user_id) or account.user_id == user_id
    rescue
      Ecto.NoResultsError -> false
    end
  end
end
