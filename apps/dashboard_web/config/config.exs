import Config

config :dashboard_web, DashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: DashboardWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: DashboardWeb.PubSub,
  live_view: [signing_salt: "your_signing_salt"]

config :dashboard_web,
  generators: [context_app: :shared_data]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason
