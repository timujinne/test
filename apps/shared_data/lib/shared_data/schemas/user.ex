defmodule SharedData.Schemas.User do
  @moduledoc """
  User schema for managing system users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :username, :string
    field :password_hash, :string
    field :is_active, :boolean, default: true
    field :last_login_at, :utc_datetime

    # Virtual field for password
    field :password, :string, virtual: true

    has_many :api_credentials, SharedData.Schemas.ApiCredential
    has_many :trades, SharedData.Schemas.Trade
    has_many :orders, SharedData.Schemas.Order
    has_many :balances, SharedData.Schemas.Balance
    has_many :settings, SharedData.Schemas.Setting

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :username, :password, :is_active, :last_login_at])
    |> validate_required([:email, :username])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset
end
