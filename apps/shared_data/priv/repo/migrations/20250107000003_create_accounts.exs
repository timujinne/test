defmodule SharedData.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :binance_account_id, :string
      add :label, :string, null: false
      add :is_active, :boolean, default: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :api_credential_id, references(:api_credentials, on_delete: :restrict, type: :binary_id), null: false

      timestamps()
    end

    create index(:accounts, [:user_id])
    create index(:accounts, [:api_credential_id])
    create unique_index(:accounts, [:user_id, :label])
  end
end
