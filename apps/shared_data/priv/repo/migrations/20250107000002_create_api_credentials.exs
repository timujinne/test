defmodule SharedData.Repo.Migrations.CreateApiCredentials do
  use Ecto.Migration

  def change do
    create table(:api_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :api_key, :binary, null: false
      add :secret_key, :binary, null: false
      add :label, :string, null: false
      add :is_active, :boolean, default: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:api_credentials, [:user_id])
  end
end
