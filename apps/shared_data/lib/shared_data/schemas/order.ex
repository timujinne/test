defmodule SharedData.Schemas.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "orders" do
    field :order_id, :string
    field :client_order_id, :string
    field :symbol, :string
    field :type, :string
    field :side, :string
    field :price, :decimal
    field :quantity, :decimal
    field :filled_qty, :decimal, default: Decimal.new(0)
    field :status, :string
    field :time_in_force, :string

    belongs_to :account, SharedData.Schemas.Account
    has_many :trades, SharedData.Schemas.Trade

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :order_id,
      :client_order_id,
      :symbol,
      :type,
      :side,
      :price,
      :quantity,
      :filled_qty,
      :status,
      :time_in_force,
      :account_id
    ])
    |> validate_required([:symbol, :type, :side, :quantity, :account_id])
    |> validate_inclusion(:type, ["LIMIT", "MARKET", "STOP_LOSS", "STOP_LOSS_LIMIT", "TAKE_PROFIT", "TAKE_PROFIT_LIMIT"])
    |> validate_inclusion(:side, ["BUY", "SELL"])
    |> validate_inclusion(:status, ["NEW", "PARTIALLY_FILLED", "FILLED", "CANCELED", "REJECTED", "EXPIRED"])
    |> unique_constraint(:order_id)
    |> foreign_key_constraint(:account_id)
  end
end
