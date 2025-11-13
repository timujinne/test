defmodule SharedData.Schemas.ApiCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_credentials" do
    field :api_key, SharedData.Encrypted.Binary
    field :secret_key, SharedData.Encrypted.Binary
    field :label, :string
    field :is_active, :boolean, default: true

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(api_credential, attrs) do
    api_credential
    |> cast(attrs, [:api_key, :secret_key, :label, :is_active, :user_id])
    |> validate_required([:api_key, :secret_key, :label, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
