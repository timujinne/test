defmodule SharedData.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :username, :string, null: false
      add :password_hash, :string
      add :is_active, :boolean, default: true, null: false
      add :last_login_at, :utc_datetime

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
  end
end
