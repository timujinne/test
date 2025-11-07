# Elixir Code Formatter Configuration
# Used by: mix format

[
  # Import dependencies for proper formatting
  # Note: Add dependencies here once they are installed in mix.exs
  # import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  import_deps: [],

  # Subdirectories to format (umbrella apps)
  subdirectories: ["apps/*"],

  # Plugins for special formatting
  # Note: Enable once Phoenix LiveView is installed
  # plugins: [Phoenix.LiveView.HTMLFormatter],
  plugins: [],

  # Input files and patterns
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "apps/*/mix.exs",
    "apps/*/lib/**/*.{ex,exs}",
    "apps/*/test/**/*.{ex,exs}",
    "apps/*/priv/*/seeds.exs",
    "priv/*/seeds.exs"
  ],

  # Line length (default: 98)
  line_length: 120,

  # Local functions without parentheses (doesn't require dependencies)
  locals_without_parens: [
      # Phoenix
      plug: 1,
      plug: 2,
      action_fallback: 1,

      # Phoenix Router
      pipe_through: 1,
      resources: 2,
      resources: 3,

      # Phoenix LiveView
      live: 2,
      live: 3,
      live_session: 2,
      live_session: 3,

      # Ecto
      field: 2,
      field: 3,
      belongs_to: 2,
      belongs_to: 3,
      has_one: 2,
      has_one: 3,
      has_many: 2,
      has_many: 3,
      many_to_many: 2,
      many_to_many: 3,
      embeds_one: 2,
      embeds_one: 3,
      embeds_many: 2,
      embeds_many: 3,

      # Ecto Migrations
      create: 1,
      create: 2,
      drop: 1,
      drop: 2,
      alter: 1,
      alter: 2,
      execute: 1,
      execute: 2,
      rename: 2,
      add: 2,
      add: 3,
      remove: 1,
      remove: 2,
      modify: 2,
      modify: 3,

      # Testing
      assert_receive: 1,
      assert_receive: 2,
      refute_receive: 1,
      refute_receive: 2,

      # Phoenix LiveView components
      attr: 2,
      attr: 3,
      slot: 1,
      slot: 2
    ]
]
