[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["apps/*"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs}",
    "{config,lib,test}/**/*.{ex,exs}",
    "apps/*/mix.exs",
    "apps/*/{config,lib,test}/**/*.{ex,exs}",
    "apps/*/priv/repo/**/*.{ex,exs}"
  ]
]
