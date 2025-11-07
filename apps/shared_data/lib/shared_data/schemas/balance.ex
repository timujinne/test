defmodule SharedData.Schemas.Balance do
  @moduledoc """
  Balance schema for tracking account balances.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "balances" do
    field :asset, :string
    field :free, :decimal
    field :locked, :decimal
    field :total, :decimal, virtual: true
    field :snapshot_at, :utc_datetime

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [:asset, :free, :locked, :snapshot_at, :user_id])
    |> validate_required([:asset, :free, :locked, :user_id])
    |> foreign_key_constraint(:user_id)
    |> calculate_total()
  end

  defp calculate_total(%Ecto.Changeset{valid?: true} = changeset) do
    free = get_field(changeset, :free) || Decimal.new(0)
    locked = get_field(changeset, :locked) || Decimal.new(0)
    put_change(changeset, :total, Decimal.add(free, locked))
  end

  defp calculate_total(changeset), do: changeset
end
