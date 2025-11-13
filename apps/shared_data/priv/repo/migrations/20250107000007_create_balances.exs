defmodule SharedData.Repo.Migrations.CreateBalances do
  use Ecto.Migration

  def change do
    create table(:balances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :asset, :string, null: false
      add :free, :decimal, precision: 20, scale: 8, null: false
      add :locked, :decimal, precision: 20, scale: 8, null: false
      add :total, :decimal, precision: 20, scale: 8
      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:balances, [:account_id])
    create unique_index(:balances, [:account_id, :asset])
  end
end
