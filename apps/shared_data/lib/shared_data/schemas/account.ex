defmodule SharedData.Schemas.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :binance_account_id, :string
    field :label, :string
    field :is_active, :boolean, default: true

    belongs_to :user, SharedData.Schemas.User
    belongs_to :api_credential, SharedData.Schemas.ApiCredential

    has_many :balances, SharedData.Schemas.Balance
    has_many :orders, SharedData.Schemas.Order
    has_many :trades, SharedData.Schemas.Trade
    has_many :settings, SharedData.Schemas.Setting

    timestamps()
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:binance_account_id, :label, :is_active, :user_id, :api_credential_id])
    |> validate_required([:label, :user_id, :api_credential_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:api_credential_id)
  end
end
