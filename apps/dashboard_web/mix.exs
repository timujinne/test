defmodule DashboardWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :dashboard_web,
      version: "1.0.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [summary: false]
    ]
  end

  def application do
    [
      mod: {DashboardWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:finch, "~> 0.18"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_ecto, "~> 4.6"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.6"},
      {:shared_data, in_umbrella: true},
      {:trading_engine, in_umbrella: true},
      # PhoenixKit - SaaS starter kit (auth, roles, admin)
      {:phoenix_kit, "~> 1.7.0"},
      # PhoenixKit modules extracted into separate packages (schema stays in
      # phoenix_kit core migrations; these provide the module code/routes/admin).
      {:phoenix_kit_publishing, "~> 0.2.0"},
      {:phoenix_kit_emails, "~> 0.1.6"},
      {:igniter, "~> 0.7"},
      # Tidewave MCP Server for AI-assisted development
      {:tidewave, "~> 0.5", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
