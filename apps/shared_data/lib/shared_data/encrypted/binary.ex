defmodule SharedData.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: SharedData.Vault
end
