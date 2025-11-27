defmodule SharedData.Repo.Migrations.AllowNullUserId do
  use Ecto.Migration

  def up do
    alter table(:api_credentials) do
      modify :user_id, :binary_id, null: true
    end

    alter table(:accounts) do
      modify :user_id, :binary_id, null: true
    end
  end

  def down do
    alter table(:api_credentials) do
      modify :user_id, :binary_id, null: false
    end

    alter table(:accounts) do
      modify :user_id, :binary_id, null: false
    end
  end
end
