defmodule SharedData.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :key, :string, null: false
      add :value, :map, null: false
      add :category, :string
      add :is_active, :boolean, default: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:settings, [:user_id])
    create index(:settings, [:category])
    create unique_index(:settings, [:user_id, :key])
  end
end
