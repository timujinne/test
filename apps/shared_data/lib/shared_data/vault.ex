defmodule SharedData.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data like API keys and secrets.

  Uses AES.GCM encryption with 256-bit keys.
  """

  use Cloak.Vault, otp_app: :shared_data
end
