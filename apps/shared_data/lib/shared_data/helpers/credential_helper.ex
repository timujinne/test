defmodule SharedData.Helpers.CredentialHelper do
  @moduledoc """
  Helper module for fetching API credentials.
  Tries to get credentials from the database first (for authenticated users),
  falls back to environment variables if not found.
  """

  alias SharedData.Credentials

  @doc """
  Gets API credentials for a user.

  First tries to get the active credential from the database.
  If not found or user_id is nil, falls back to environment variables.

  ## Examples

      iex> get_credentials(user_id)
      {api_key, secret_key}

      iex> get_credentials(nil)
      {api_key_from_env, secret_key_from_env}

  Returns `nil` if no credentials are found.
  """
  def get_credentials(user_id \\ nil, opts \\ [])

  def get_credentials(nil, _opts) do
    # No user authenticated, try env vars
    get_credentials_from_env()
  end

  def get_credentials(user_id, opts) do
    # Try to get active credential from database
    case Credentials.get_active_credential(user_id, opts) do
      nil ->
        # Fall back to env vars
        get_credentials_from_env()

      credential ->
        {credential.api_key, credential.secret_key}
    end
  end

  @doc """
  Gets API credentials from environment variables.

  Returns `nil` if environment variables are not set.

  ## Examples

      iex> get_credentials_from_env()
      {api_key, secret_key}

  """
  def get_credentials_from_env do
    api_key = System.get_env("BINANCE_API_KEY")
    secret_key = System.get_env("BINANCE_SECRET_KEY")

    if api_key && secret_key do
      {api_key, secret_key}
    else
      nil
    end
  end

  @doc """
  Masks an API key, showing only the last 4 characters.

  ## Examples

      iex> mask_key("1234567890abcdef")
      "************cdef"

      iex> mask_key("abc")
      "***"

  """
  def mask_key(nil), do: "N/A"

  def mask_key(key) when is_binary(key) do
    key_length = String.length(key)

    cond do
      key_length <= 4 ->
        String.duplicate("*", key_length)

      key_length <= 8 ->
        visible = String.slice(key, -4, 4)
        String.duplicate("*", 4) <> visible

      true ->
        visible = String.slice(key, -4, 4)
        String.duplicate("*", 12) <> visible
    end
  end

  @doc """
  Validates that credentials are present and non-empty.

  ## Examples

      iex> valid_credentials?({"key", "secret"})
      true

      iex> valid_credentials?(nil)
      false

      iex> valid_credentials?({"", "secret"})
      false

  """
  def valid_credentials?(nil), do: false

  def valid_credentials?({api_key, secret_key})
      when is_binary(api_key) and is_binary(secret_key) do
    String.length(api_key) > 0 && String.length(secret_key) > 0
  end

  def valid_credentials?(_), do: false
end
