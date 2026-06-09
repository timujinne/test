defmodule SharedData.Repo.Migrations.CreateTradesHypertable do
  use Ecto.Migration

  def up do
    create table(:trades, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :commission, :decimal, precision: 20, scale: 8
      add :commission_asset, :string
      add :pnl, :decimal, precision: 20, scale: 8
      add :timestamp, :utc_datetime_usec, null: false

      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id),
        null: false

      add :order_id, references(:orders, on_delete: :nilify_all, type: :binary_id)

      timestamps()
    end

    create index(:trades, [:account_id])
    create index(:trades, [:symbol])
    create index(:trades, [:timestamp])
    create index(:trades, [:account_id, :timestamp])
  end

  def down do
    drop table(:trades)
  end
end
