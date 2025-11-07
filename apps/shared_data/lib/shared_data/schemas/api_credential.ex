defmodule SharedData.Schemas.ApiCredential do
  @moduledoc """
  API Credential schema for storing encrypted Binance API keys.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "api_credentials" do
    field :name, :string
    field :api_key, SharedData.Encrypted.Binary
    field :secret_key, SharedData.Encrypted.Binary
    field :is_testnet, :boolean, default: true
    field :is_active, :boolean, default: true
    field :permissions, {:array, :string}, default: []
    field :last_used_at, :utc_datetime

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(api_credential, attrs) do
    api_credential
    |> cast(attrs, [:name, :api_key, :secret_key, :is_testnet, :is_active, :permissions, :user_id])
    |> validate_required([:name, :api_key, :secret_key, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
