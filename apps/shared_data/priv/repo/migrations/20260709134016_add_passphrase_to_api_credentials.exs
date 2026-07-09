defmodule SharedData.Repo.Migrations.AddPassphraseToApiCredentials do
  use Ecto.Migration

  def change do
    alter table(:api_credentials) do
      add :passphrase, :binary, null: true
    end
  end
end
