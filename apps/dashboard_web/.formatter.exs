[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs}",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/repo/**/*.{ex,exs}"
  ]
]
