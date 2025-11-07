defmodule SharedData.Repo.Migrations.CreateTrades do
  use Ecto.Migration

  def change do
    create table(:trades) do
      add :exchange_trade_id, :string
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :quote_quantity, :decimal, precision: 20, scale: 8
      add :commission, :decimal, precision: 20, scale: 8
      add :commission_asset, :string
      add :realized_pnl, :decimal, precision: 20, scale: 8
      add :executed_at, :utc_datetime, null: false
      add :strategy, :string
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :order_id, references(:orders, on_delete: :nilify_all)

      timestamps()
    end

    create index(:trades, [:user_id])
    create index(:trades, [:order_id])
    create index(:trades, [:symbol])
    create index(:trades, [:executed_at])
    create index(:trades, [:exchange_trade_id])

    # Create TimescaleDB hypertable for time-series optimization
    # This will be executed if TimescaleDB extension is available
    execute(
      "SELECT create_hypertable('trades', 'executed_at', if_not_exists => TRUE, migrate_data => TRUE);",
      "SELECT 1;" # Reverse migration - do nothing
    )
  end
end
