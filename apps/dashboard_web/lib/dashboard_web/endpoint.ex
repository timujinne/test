defmodule DashboardWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dashboard_web

  # Session configuration - security hardened
  # signing_salt is NOT a secret, it adds uniqueness to signatures
  # SECRET_KEY_BASE (from env) is the actual secret
  @session_options [
    store: :cookie,
    key: "_dashboard_web_key",
    # Static salt, combined with SECRET_KEY_BASE
    signing_salt: "Kx8mP2vQ7nL3",
    # Prevents CSRF via cross-site requests
    same_site: "Strict",
    # 7 days
    max_age: 86_400 * 7
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :dashboard_web,
    gzip: false,
    only: DashboardWeb.static_paths()

  # Tidewave MCP Server for AI-assisted development (dev only).
  # NOTE: do NOT set allow_remote_access: true — it disables Tidewave's
  # built-in loopback-only guard and exposes code/DB execution to any
  # reachable client. Keep it loopback-only.
  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug DashboardWeb.Router
end
