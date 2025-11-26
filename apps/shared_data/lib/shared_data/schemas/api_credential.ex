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
    field :is_testnet, :boolean, default: false

    belongs_to :user, SharedData.Schemas.User

    timestamps()
  end

  @doc false
  def changeset(api_credential, attrs) do
    api_credential
    |> cast(attrs, [:api_key, :secret_key, :label, :is_active, :is_testnet, :user_id])
    |> validate_required([:api_key, :secret_key, :label])
    |> validate_length(:label, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
    |> ensure_only_one_active()
  end

  defp ensure_only_one_active(changeset) do
    # If this credential is being set to active, deactivate all others for the same user
    # The actual deactivation logic is handled in the Credentials context module
    changeset
  end
end
