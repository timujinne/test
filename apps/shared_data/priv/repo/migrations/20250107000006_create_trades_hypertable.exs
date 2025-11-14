defmodule SharedData.Repo.Migrations.CreateTradesHypertable do
  use Ecto.Migration

  def up do
    create table(:trades, primary_key: false) do
      add :id, :binary_id, null: false
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :commission, :decimal, precision: 20, scale: 8
      add :commission_asset, :string
      add :pnl, :decimal, precision: 20, scale: 8
      add :timestamp, :utc_datetime_usec, null: false
      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id), null: false
      add :order_id, references(:orders, on_delete: :nilify_all, type: :binary_id)

      timestamps()
    end

    # Create composite primary key with timestamp for TimescaleDB hypertable
    create unique_index(:trades, [:id, :timestamp], primary: true)

    create index(:trades, [:account_id])
    create index(:trades, [:symbol])
    create index(:trades, [:timestamp])

    # Convert to TimescaleDB hypertable
    execute "SELECT create_hypertable('trades', 'timestamp')"

    # Create continuous aggregates for daily statistics
    execute """
    CREATE MATERIALIZED VIEW trades_daily
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('1 day', timestamp) AS bucket,
      account_id,
      symbol,
      COUNT(*) as trade_count,
      SUM(CASE WHEN side = 'BUY' THEN quantity ELSE 0 END) as buy_volume,
      SUM(CASE WHEN side = 'SELL' THEN quantity ELSE 0 END) as sell_volume,
      SUM(pnl) as total_pnl
    FROM trades
    GROUP BY bucket, account_id, symbol
    """

    # Refresh policy for the continuous aggregate
    execute """
    SELECT add_continuous_aggregate_policy('trades_daily',
      start_offset => INTERVAL '3 days',
      end_offset => INTERVAL '1 hour',
      schedule_interval => INTERVAL '1 hour')
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS trades_daily"
    drop table(:trades)
  end
end
