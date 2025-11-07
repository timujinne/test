defmodule SharedData.Schemas.Order do
  @moduledoc """
  Order schema for tracking orders placed on Binance.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :exchange_order_id, :string
    field :client_order_id, :string
    field :symbol, :string
    # "BUY" or "SELL"
    field :side, :string
    # "LIMIT", "MARKET", "STOP_LOSS", etc.
    field :type, :string
    # "GTC", "IOC", "FOK"
    field :time_in_force, :string
    field :price, :decimal
    field :quantity, :decimal
    field :stop_price, :decimal
    # "NEW", "FILLED", "PARTIALLY_FILLED", "CANCELED", etc.
    field :status, :string
    field :executed_quantity, :decimal
    field :cumulative_quote_quantity, :decimal
    field :strategy, :string
    field :placed_at, :utc_datetime
    field :updated_at_exchange, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, SharedData.Schemas.User
    has_many :trades, SharedData.Schemas.Trade

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :exchange_order_id,
      :client_order_id,
      :symbol,
      :side,
      :type,
      :time_in_force,
      :price,
      :quantity,
      :stop_price,
      :status,
      :executed_quantity,
      :cumulative_quote_quantity,
      :strategy,
      :placed_at,
      :updated_at_exchange,
      :metadata,
      :user_id
    ])
    |> validate_required([:symbol, :side, :type, :quantity, :status, :user_id])
    |> validate_inclusion(:side, ["BUY", "SELL"])
    |> validate_inclusion(:type, ["LIMIT", "MARKET", "STOP_LOSS", "STOP_LOSS_LIMIT", "TAKE_PROFIT", "TAKE_PROFIT_LIMIT"])
    |> foreign_key_constraint(:user_id)
  end
end
