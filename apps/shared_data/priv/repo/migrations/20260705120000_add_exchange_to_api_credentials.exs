defmodule SharedData.Repo.Migrations.AddExchangeToApiCredentials do
  use Ecto.Migration

  def change do
    alter table(:api_credentials) do
      add :exchange, :string, default: "binance", null: false
    end
  end
end
