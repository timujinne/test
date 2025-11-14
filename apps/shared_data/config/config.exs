import Config

# Configure SharedData Repo
config :shared_data, SharedData.Repo,
  database: "binance_trading_repo",
  pool_size: 10

# Configure Cloak Vault
# Use CLOAK_KEY environment variable or fallback to development key
# Generate production key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.get_env("CLOAK_KEY") || "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
      iv_length: 12
    }
  ]
