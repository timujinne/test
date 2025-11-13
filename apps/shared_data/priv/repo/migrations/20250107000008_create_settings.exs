defmodule SharedData.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :strategy_name, :string, null: false
      add :config, :map, null: false
      add :is_active, :boolean, default: false
      add :account_id, references(:accounts, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:settings, [:account_id])
    create index(:settings, [:is_active])
  end
end
