---
name: elixir-deployment
description: Production deployment guide for Elixir applications including Mix Release, Docker, clustering, and monitoring. Use when deploying Elixir apps to production environments.
---

# Elixir Production Deployment

## Mix Release

```elixir
# mix.exs
def project do
  [
    releases: [
      production: [
        include_executables_for: [:unix],
        applications: [
          runtime_tools: :permanent,
          my_app: :permanent
        ]
      ]
    ]
  ]
end

# Build release
MIX_ENV=prod mix release

# Run
_build/prod/rel/my_app/bin/my_app start
_build/prod/rel/my_app/bin/my_app daemon
```

## Dockerfile

```dockerfile
FROM elixir:1.16-alpine AS build

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
COPY priv priv
RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix release

FROM alpine:3.19
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/my_app ./

EXPOSE 4000
CMD ["bin/my_app", "start"]
```

## Clustering

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    k8s: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        kubernetes_namespace: "production",
        kubernetes_selector: "app=myapp",
        polling_interval: 10_000
      ]
    ]
  ]
```
