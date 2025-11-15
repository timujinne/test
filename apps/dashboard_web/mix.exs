defmodule DashboardWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :dashboard_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        summary: [threshold: 0],
        ignore_modules: [
          ~r/\.Endpoint$/,
          ~r/\.Router$/,
          ~r/\.Telemetry$/,
          ~r/\.Layouts$/,
          ~r/\.Gettext$/,
          ~r/\.ErrorHTML$/,
          ~r/\.CoreComponents$/,
          ~r/Live$/
        ]
      ]
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
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.6"},
      {:shared_data, in_umbrella: true},
      {:trading_engine, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
