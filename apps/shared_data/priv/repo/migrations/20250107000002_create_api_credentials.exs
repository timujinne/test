defmodule SharedData.Repo.Migrations.CreateApiCredentials do
  use Ecto.Migration

  def change do
    create table(:api_credentials) do
      add :name, :string, null: false
      add :api_key, :binary, null: false
      add :secret_key, :binary, null: false
      add :is_testnet, :boolean, default: true, null: false
      add :is_active, :boolean, default: true, null: false
      add :permissions, {:array, :string}, default: []
      add :last_used_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:api_credentials, [:user_id])
    create index(:api_credentials, [:is_active])
  end
end
