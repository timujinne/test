defmodule SharedData.Repo.Migrations.AddIsTestnetToApiCredentials do
  use Ecto.Migration

  def change do
    alter table(:api_credentials) do
      add :is_testnet, :boolean, default: false, null: false
    end
  end
end
