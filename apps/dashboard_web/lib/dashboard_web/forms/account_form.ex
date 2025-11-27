defmodule DashboardWeb.Forms.AccountForm do
  @moduledoc """
  Virtual schema for combined Account + API Credentials form.
  Used to properly handle form validation without losing field values.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :label, :string
    field :api_key, :string
    field :secret_key, :string
    field :is_testnet, :boolean, default: false
    field :binance_account_id, :string
    field :is_active, :boolean, default: true
  end

  @doc """
  Changeset for creating new account with credentials.
  API key and secret key are required.
  """
  def changeset(form, attrs \\ %{}) do
    # Convert checkbox "on" values to boolean
    attrs = normalize_booleans(attrs)

    form
    |> cast(attrs, [:label, :api_key, :secret_key, :is_testnet, :binance_account_id, :is_active])
    |> validate_required([:label, :api_key, :secret_key])
    |> validate_length(:label, min: 1, max: 255)
    |> validate_length(:api_key, min: 10, message: "must be at least 10 characters")
    |> validate_length(:secret_key, min: 10, message: "must be at least 10 characters")
  end

  @doc """
  Changeset for editing existing account.
  API key and secret key are optional - leave empty to keep current values.
  """
  def changeset_for_edit(form, attrs \\ %{}) do
    attrs = normalize_booleans(attrs)

    form
    |> cast(attrs, [:label, :api_key, :secret_key, :is_testnet, :binance_account_id, :is_active])
    |> validate_required([:label])
    |> validate_length(:label, min: 1, max: 255)
    |> maybe_validate_keys()
  end

  defp normalize_booleans(attrs) when is_map(attrs) do
    attrs
    |> maybe_convert_boolean("is_testnet", false)
    |> maybe_convert_boolean("is_active", true)
  end

  defp maybe_convert_boolean(attrs, key, default) do
    case Map.get(attrs, key) do
      "on" -> Map.put(attrs, key, true)
      "off" -> Map.put(attrs, key, false)
      nil -> Map.put(attrs, key, default)
      val when is_boolean(val) -> attrs
      _ -> Map.put(attrs, key, default)
    end
  end

  defp maybe_validate_keys(changeset) do
    api_key = get_change(changeset, :api_key)
    secret_key = get_change(changeset, :secret_key)

    changeset =
      if api_key && api_key != "" do
        validate_length(changeset, :api_key, min: 10, message: "must be at least 10 characters")
      else
        changeset
      end

    if secret_key && secret_key != "" do
      validate_length(changeset, :secret_key, min: 10, message: "must be at least 10 characters")
    else
      changeset
    end
  end

  @doc """
  Creates a new empty form struct.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a form struct pre-filled with data from an existing account.
  """
  def from_account(account) do
    %__MODULE__{
      label: account.label,
      binance_account_id: account.binance_account_id,
      is_active: account.is_active,
      is_testnet: account.api_credential && account.api_credential.is_testnet
    }
  end
end
