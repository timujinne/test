defmodule SharedData.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :exchange_order_id, :string
      add :client_order_id, :string
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :type, :string, null: false
      add :time_in_force, :string
      add :price, :decimal, precision: 20, scale: 8
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :stop_price, :decimal, precision: 20, scale: 8
      add :status, :string, null: false
      add :executed_quantity, :decimal, precision: 20, scale: 8, default: 0
      add :cumulative_quote_quantity, :decimal, precision: 20, scale: 8, default: 0
      add :strategy, :string
      add :placed_at, :utc_datetime
      add :updated_at_exchange, :utc_datetime
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:orders, [:user_id])
    create index(:orders, [:symbol])
    create index(:orders, [:status])
    create index(:orders, [:exchange_order_id])
    create index(:orders, [:placed_at])
  end
end
