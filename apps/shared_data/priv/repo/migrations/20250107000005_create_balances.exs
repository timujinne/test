defmodule SharedData.Repo.Migrations.CreateBalances do
  use Ecto.Migration

  def change do
    create table(:balances) do
      add :asset, :string, null: false
      add :free, :decimal, precision: 20, scale: 8, null: false, default: 0
      add :locked, :decimal, precision: 20, scale: 8, null: false, default: 0
      add :snapshot_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:balances, [:user_id])
    create index(:balances, [:asset])
    create index(:balances, [:user_id, :asset])
    create index(:balances, [:snapshot_at])
  end
end
