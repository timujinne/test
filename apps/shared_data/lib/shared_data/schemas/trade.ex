defmodule SharedData.Schemas.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trades" do
    field :symbol, :string
    field :side, :string
    field :price, :decimal
    field :quantity, :decimal
    field :commission, :decimal
    field :commission_asset, :string
    field :pnl, :decimal
    field :timestamp, :utc_datetime_usec

    belongs_to :account, SharedData.Schemas.Account
    belongs_to :order, SharedData.Schemas.Order

    timestamps()
  end

  @doc false
  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :symbol,
      :side,
      :price,
      :quantity,
      :commission,
      :commission_asset,
      :pnl,
      :timestamp,
      :account_id,
      :order_id
    ])
    |> validate_required([:symbol, :side, :price, :quantity, :timestamp, :account_id])
    |> validate_inclusion(:side, ["BUY", "SELL"])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:order_id)
  end
end
