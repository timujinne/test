defmodule SharedData.Credentials do
  @moduledoc """
  Context module for managing API credentials.
  """

  import Ecto.Query, warn: false
  alias SharedData.Repo
  alias SharedData.Schemas.ApiCredential

  @doc """
  Lists all credentials for a given user.

  ## Examples

      iex> list_credentials(user_id)
      [%ApiCredential{}, ...]

  """
  def list_credentials(user_id) do
    query =
      ApiCredential
      |> order_by([c], [desc: c.is_active, asc: c.label])

    query =
      if is_nil(user_id) do
        where(query, [c], is_nil(c.user_id))
      else
        where(query, [c], c.user_id == ^user_id)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single credential by ID.

  Returns `nil` if the credential does not exist.

  ## Examples

      iex> get_credential(id)
      %ApiCredential{}

      iex> get_credential(bad_id)
      nil

  """
  def get_credential(id) do
    Repo.get(ApiCredential, id)
  end

  @doc """
  Gets a single credential by ID, scoped to a specific user.

  Returns `nil` if the credential does not exist or doesn't belong to the user.

  ## Examples

      iex> get_credential(id, user_id)
      %ApiCredential{}

      iex> get_credential(bad_id, user_id)
      nil

  """
  def get_credential(id, user_id) do
    query =
      ApiCredential
      |> where([c], c.id == ^id)

    query =
      if is_nil(user_id) do
        where(query, [c], is_nil(c.user_id))
      else
        where(query, [c], c.user_id == ^user_id)
      end

    Repo.one(query)
  end

  @doc """
  Gets the active credential for a user.

  Returns `nil` if no active credential exists.

  ## Examples

      iex> get_active_credential(user_id)
      %ApiCredential{}

      iex> get_active_credential(bad_user_id)
      nil

  """
  def get_active_credential(user_id) do
    query =
      ApiCredential
      |> where([c], c.is_active == true)

    query =
      if is_nil(user_id) do
        where(query, [c], is_nil(c.user_id))
      else
        where(query, [c], c.user_id == ^user_id)
      end

    Repo.one(query)
  end

  @doc """
  Gets the active credential for a user, optionally filtering by testnet status.

  Returns `nil` if no matching credential exists.

  ## Examples

      iex> get_active_credential(user_id, is_testnet: true)
      %ApiCredential{}

  """
  def get_active_credential(user_id, opts) do
    query =
      ApiCredential
      |> where([c], c.is_active == true)

    query =
      if is_nil(user_id) do
        where(query, [c], is_nil(c.user_id))
      else
        where(query, [c], c.user_id == ^user_id)
      end

    query =
      if Keyword.has_key?(opts, :is_testnet) do
        is_testnet = Keyword.get(opts, :is_testnet)
        where(query, [c], c.is_testnet == ^is_testnet)
      else
        query
      end

    Repo.one(query)
  end

  @doc """
  Creates a credential.

  ## Examples

      iex> create_credential(%{field: value})
      {:ok, %ApiCredential{}}

      iex> create_credential(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_credential(attrs \\ %{}) do
    %ApiCredential{}
    |> ApiCredential.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, credential} ->
        # If this credential is active, deactivate all others for this user
        if credential.is_active do
          deactivate_other_credentials(credential.user_id, credential.id)
        end

        {:ok, credential}

      error ->
        error
    end
  end

  @doc """
  Updates a credential.

  ## Examples

      iex> update_credential(credential, %{field: new_value})
      {:ok, %ApiCredential{}}

      iex> update_credential(credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_credential(%ApiCredential{} = credential, attrs) do
    credential
    |> ApiCredential.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_credential} ->
        # If this credential was set to active, deactivate all others for this user
        if updated_credential.is_active do
          deactivate_other_credentials(updated_credential.user_id, updated_credential.id)
        end

        {:ok, updated_credential}

      error ->
        error
    end
  end

  @doc """
  Deletes a credential.

  ## Examples

      iex> delete_credential(credential)
      {:ok, %ApiCredential{}}

      iex> delete_credential(credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_credential(%ApiCredential{} = credential) do
    Repo.delete(credential)
  end

  @doc """
  Sets a credential as the active one for a user.
  Deactivates all other credentials for that user.

  ## Examples

      iex> set_active_credential(credential_id, user_id)
      {:ok, %ApiCredential{}}

      iex> set_active_credential(bad_id, user_id)
      {:error, :not_found}

  """
  def set_active_credential(credential_id, user_id) do
    case get_credential(credential_id, user_id) do
      nil ->
        {:error, :not_found}

      credential ->
        # Deactivate all other credentials first
        deactivate_other_credentials(user_id, credential_id)

        # Activate this one
        update_credential(credential, %{is_active: true})
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking credential changes.

  ## Examples

      iex> change_credential(credential)
      %Ecto.Changeset{data: %ApiCredential{}}

  """
  def change_credential(%ApiCredential{} = credential, attrs \\ %{}) do
    ApiCredential.changeset(credential, attrs)
  end

  @doc """
  Tests a credential by making a request to Binance.

  ## Examples

      iex> test_credential(credential)
      {:ok, %{account_type: "SPOT", ...}}

      iex> test_credential(bad_credential)
      {:error, "Invalid API key"}

  """
  def test_credential(%ApiCredential{} = credential) do
    # Use runtime module lookup to avoid compile-time dependency on DataCollector
    # SharedData compiles before DataCollector, so we use apply/3
    apply(DataCollector.BinanceClient, :get_account, [credential.api_key, credential.secret_key])
  end

  # Private functions

  defp deactivate_other_credentials(user_id, except_id) do
    query =
      ApiCredential
      |> where([c], c.id != ^except_id)

    query =
      if is_nil(user_id) do
        where(query, [c], is_nil(c.user_id))
      else
        where(query, [c], c.user_id == ^user_id)
      end

    Repo.update_all(query, set: [is_active: false])
  end
end
