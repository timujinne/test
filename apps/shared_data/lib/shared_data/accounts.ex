defmodule SharedData.Accounts do
  @moduledoc """
  Context для управления пользователями и API credentials.
  """

  import Ecto.Query, warn: false
  alias SharedData.Repo
  alias SharedData.Schemas.{User, ApiCredential, Account}

  ## User functions

  @doc """
  Создает нового пользователя.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получить пользователя по email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Получить пользователя по ID.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Аутентификация пользователя по email и паролю.
  """
  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && Argon2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      true ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc """
  Список всех пользователей.
  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Обновить пользователя.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Удалить пользователя.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  ## API Credential functions

  @doc """
  Создать API credential для пользователя.
  """
  def create_api_credential(user_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :user_id, user_id)

    %ApiCredential{}
    |> ApiCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получить все API credentials пользователя.
  """
  def list_user_api_credentials(user_id) do
    ApiCredential
    |> where([c], c.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Получить API credential по ID.
  """
  def get_api_credential!(id), do: Repo.get!(ApiCredential, id)

  @doc """
  Обновить API credential.
  """
  def update_api_credential(%ApiCredential{} = credential, attrs) do
    credential
    |> ApiCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Деактивировать API credential.
  """
  def deactivate_api_credential(%ApiCredential{} = credential) do
    update_api_credential(credential, %{is_active: false})
  end

  @doc """
  Удалить API credential.
  """
  def delete_api_credential(%ApiCredential{} = credential) do
    Repo.delete(credential)
  end

  ## Account functions

  @doc """
  Создать аккаунт.
  """
  def create_account(user_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :user_id, user_id)

    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получить все аккаунты пользователя.
  """
  def list_user_accounts(user_id) do
    query =
      Account
      |> order_by([a], desc: a.is_active, asc: a.label)
      |> preload([:api_credential, :balances, :settings])

    query =
      if is_nil(user_id) do
        where(query, [a], is_nil(a.user_id))
      else
        where(query, [a], a.user_id == ^user_id)
      end

    Repo.all(query)
  end

  @doc """
  Получить активные аккаунты пользователя.
  """
  def list_active_user_accounts(user_id) do
    Account
    |> where([a], a.user_id == ^user_id and a.is_active == true)
    |> preload([:api_credential, :balances, :settings])
    |> Repo.all()
  end

  @doc """
  Получить аккаунт по ID.
  """
  def get_account!(id) do
    Account
    |> preload([:api_credential, :balances, :settings])
    |> Repo.get!(id)
  end

  @doc """
  Обновить аккаунт.
  """
  def update_account(%Account{} = account, attrs) do
    account
    |> Account.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Деактивировать аккаунт.
  """
  def deactivate_account(%Account{} = account) do
    update_account(account, %{is_active: false})
  end

  @doc """
  Удалить аккаунт.
  """
  def delete_account(%Account{} = account) do
    Repo.delete(account)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account changes.
  """
  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.changeset(account, attrs)
  end

  @doc """
  Gets a single account by ID, scoped to a specific user.
  """
  def get_account_by_user(id, user_id) do
    query =
      Account
      |> where([a], a.id == ^id)
      |> preload(:api_credential)

    query =
      if is_nil(user_id) do
        where(query, [a], is_nil(a.user_id))
      else
        where(query, [a], a.user_id == ^user_id)
      end

    Repo.one(query)
  end
end
