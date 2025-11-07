defmodule SharedData.Schemas.Trade do
  @moduledoc """
  Trade schema for storing executed trades.
  Uses TimescaleDB hypertable for efficient time-series storage.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "trades" do
    field :exchange_trade_id, :string
    field :symbol, :string
    # "BUY" or "SELL"
    field :side, :string
    field :price, :decimal
    field :quantity, :decimal
    field :quote_quantity, :decimal
    field :commission, :decimal
    field :commission_asset, :string
    field :realized_pnl, :decimal
    field :executed_at, :utc_datetime
    field :strategy, :string
    field :metadata, :map, default: %{}

    belongs_to :user, SharedData.Schemas.User
    belongs_to :order, SharedData.Schemas.Order

    timestamps()
  end

  @doc false
  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :exchange_trade_id,
      :symbol,
      :side,
      :price,
      :quantity,
      :quote_quantity,
      :commission,
      :commission_asset,
      :realized_pnl,
      :executed_at,
      :strategy,
      :metadata,
      :user_id,
      :order_id
    ])
    |> validate_required([:symbol, :side, :price, :quantity, :executed_at, :user_id])
    |> validate_inclusion(:side, ["BUY", "SELL"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:order_id)
  end
end
