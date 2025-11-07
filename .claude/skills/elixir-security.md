---
name: elixir-security
description: Security best practices for Elixir applications including encryption with Cloak, secure credential management, process isolation, and audit logging. This skill should be used when implementing secure storage of API keys, sensitive data encryption, or building security-critical applications.
---

# Elixir Security Patterns

Comprehensive security guide for production Elixir applications.

## Encryption with Cloak

### Setup

```elixir
# mix.exs
{:cloak, "~> 1.1"},
{:cloak_ecto, "~> 1.2"}

# Generate encryption key
# iex> 32 |> :crypto.strong_rand_bytes() |> Base.encode64()

# config/runtime.exs
config :my_app, MyApp.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.fetch_env!("CLOAK_KEY")),
      iv_length: 12
    }
  ]
```

### Vault Implementation

```elixir
defmodule MyApp.Vault do
  use Cloak.Vault, otp_app: :my_app
end

# Application supervision
def start(_type, _args) do
  children = [
    MyApp.Vault,
    MyApp.Repo
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### Encrypted Schema

```elixir
defmodule MyApp.ApiCredential do
  use Ecto.Schema

  schema "api_credentials" do
    field :label, :string
    field :api_key, MyApp.Encrypted.Binary
    field :api_secret, MyApp.Encrypted.Binary
    field :user_id, :binary_id
    timestamps()
  end
end

defmodule MyApp.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: MyApp.Vault
end
```

## Secure Configuration

### Runtime Secrets

```elixir
# config/runtime.exs - NEVER config.exs!
import Config

if config_env() == :prod do
  config :my_app, MyApp.BinanceClient,
    api_key: System.fetch_env!("BINANCE_API_KEY"),
    api_secret: System.fetch_env!("BINANCE_API_SECRET")

  config :my_app, MyApp.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1",
        key: Base.decode64!(System.fetch_env!("CLOAK_KEY"))
      }
    ]
end
```

## Process Isolation

### Per-Account Isolation

```elixir
defmodule TradingSystem.AccountEngine do
  use GenServer

  def start_link(account_id) do
    name = {:via, Registry, {TradingRegistry, {:account, account_id}}}
    GenServer.start_link(__MODULE__, account_id, name: name)
  end

  def init(account_id) do
    # Load encrypted credentials
    credentials = load_credentials(account_id)
    
    # Each account has isolated state
    {:ok, %{
      account_id: account_id,
      api_key: decrypt(credentials.api_key),
      api_secret: decrypt(credentials.api_secret),
      balances: %{},
      orders: %{}
    }}
  end

  defp load_credentials(account_id) do
    Repo.get_by!(ApiCredential, account_id: account_id)
  end

  defp decrypt(encrypted_value) do
    MyApp.Vault.decrypt!(encrypted_value)
  end
end
```

## Audit Logging

```elixir
defmodule MyApp.AuditLog do
  use Ecto.Schema

  schema "audit_logs" do
    field :user_id, :binary_id
    field :action, :string
    field :resource, :string
    field :changes, :map
    field :ip_address, :string
    field :user_agent, :string
    timestamps(updated_at: false)
  end

  def log(user_id, action, resource, changes \\ %{}) do
    %__MODULE__{}
    |> change(%{
      user_id: user_id,
      action: action,
      resource: resource,
      changes: changes
    })
    |> Repo.insert()
  end
end

# Usage
def place_order(account_id, params) do
  case execute_order(account_id, params) do
    {:ok, order} ->
      AuditLog.log(account_id, "place_order", "order", order)
      {:ok, order}
    error -> error
  end
end
```

## Best Practices

1. **Never hardcode secrets** - Use environment variables
2. **Encrypt at rest** - Use Cloak for sensitive data
3. **Process isolation** - One GenServer per account/user
4. **Audit everything** - Log all sensitive operations
5. **Rotate keys** - Implement key rotation strategy
6. **Use HTTPS** - Always in production
7. **Rate limiting** - Prevent abuse
8. **Input validation** - Sanitize all user input
