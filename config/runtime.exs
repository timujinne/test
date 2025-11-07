import Config

# Runtime production configuration
if config_env() == :prod do
  # Binance API configuration
  config :binance,
    api_key: System.fetch_env!("BINANCE_API_KEY"),
    secret_key: System.fetch_env!("BINANCE_SECRET_KEY"),
    end_point: System.get_env("BINANCE_BASE_URL", "https://api.binance.com")

  # Database configuration
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :shared_data, SharedData.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # Cloak encryption configuration
  config :shared_data, SharedData.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1",
        key: Base.decode64!(System.fetch_env!("CLOAK_KEY")),
        iv_length: 12
      }
    ]

  # Phoenix endpoint configuration
  config :dashboard_web, DashboardWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  # Redis configuration (optional)
  if redis_url = System.get_env("REDIS_URL") do
    config :binance_system, :redis_url, redis_url
  end
end
