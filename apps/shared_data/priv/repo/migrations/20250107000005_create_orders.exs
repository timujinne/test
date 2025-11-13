defmodule SharedData.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, :string
      add :client_order_id, :string
      add :symbol, :string, null: false
      add :type, :string, null: false
      add :side, :string, null: false
      add :price, :decimal, precision: 20, scale: 8
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :filled_qty, :decimal, precision: 20, scale: 8, default: 0
      add :status, :string
      add :time_in_force, :string
      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:orders, [:account_id])
    create index(:orders, [:symbol])
    create index(:orders, [:status])
    create unique_index(:orders, [:order_id])
  end
end
