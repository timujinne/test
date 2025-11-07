defmodule SharedData.Schemas.Setting do
  @moduledoc """
  Setting schema for storing user trading preferences and strategy configurations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "settings" do
    field :key, :string
    field :value, :map
    field :category, :string # "trading", "notification", "risk_management", etc.
    field :is_active, :boolean, default: true

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :category, :is_active, :user_id])
    |> validate_required([:key, :value, :user_id])
    |> unique_constraint([:user_id, :key])
    |> foreign_key_constraint(:user_id)
  end
end
