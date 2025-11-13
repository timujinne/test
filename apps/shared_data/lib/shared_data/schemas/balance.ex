defmodule SharedData.Schemas.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "balances" do
    field :asset, :string
    field :free, :decimal
    field :locked, :decimal
    field :total, :decimal

    belongs_to :account, SharedData.Schemas.Account

    timestamps()
  end

  @doc false
  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [:asset, :free, :locked, :total, :account_id])
    |> validate_required([:asset, :free, :locked, :account_id])
    |> put_total()
    |> unique_constraint([:account_id, :asset])
    |> foreign_key_constraint(:account_id)
  end

  defp put_total(%Ecto.Changeset{changes: %{free: free, locked: locked}} = changeset) do
    total = Decimal.add(free, locked)
    put_change(changeset, :total, total)
  end

  defp put_total(changeset), do: changeset
end
