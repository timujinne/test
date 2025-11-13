import Config

# Configure SharedData Repo
config :shared_data, SharedData.Repo,
  database: "binance_trading_repo",
  pool_size: 10

# Configure Cloak Vault
config :shared_data, SharedData.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("your-key-here"), iv_length: 12}
  ]
