defmodule SharedData.Encrypted.Binary do
  @moduledoc """
  Custom Ecto type for encrypted binary fields using Cloak.
  Used for storing sensitive data like API keys.
  """

  use Cloak.Ecto.Binary, vault: SharedData.Vault
end
