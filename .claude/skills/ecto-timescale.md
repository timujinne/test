---
name: ecto-timescale
description: Guide for using Ecto with TimescaleDB for time-series data in Elixir applications. This skill should be used when working with trade histories, market data, time-series analytics, or any application requiring optimized storage and querying of timestamped data.
---

# Ecto + TimescaleDB Integration

Complete guide for managing time-series data with Ecto and TimescaleDB in Elixir.

## When to Use This Skill

- Storing cryptocurrency trade histories
- Market data and price histories
- Time-series analytics and aggregations
- High-volume timestamped data
- Continuous aggregates for pre-computed metrics

## Setup and Configuration

### Database Setup

```elixir
# mix.exs
defp deps do
  [
    {:ecto_sql, "~> 3.11"},
    {:postgrex, "~> 0.17"},
    {:timescale, "~> 0.1"}  # Helper library
  ]
end

# config/config.exs
config :my_app, MyApp.Repo,
  database: "myapp_db",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
```

### Creating Hypertables

```elixir
defmodule MyApp.Repo.Migrations.CreateTradesHypertable do
  use Ecto.Migration

  def up do
    # Enable TimescaleDB extension
    execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"

    create table(:trades, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :price, :decimal, precision: 28, scale: 8
      add :quantity, :decimal, precision: 28, scale: 18
      add :user_id, :binary_id
    end

    # Convert to hypertable - partitions by time
    execute """
    SELECT create_hypertable('trades', 'timestamp',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    )
    """

    # Create indexes
    create index(:trades, [:symbol, :timestamp])
    create index(:trades, [:user_id, :timestamp])

    # Enable compression after 7 days
    execute """
    ALTER TABLE trades SET (
      timescaledb.compress,
      timescaledb.compress_segmentby = 'symbol,user_id'
    )
    """

    execute """
    SELECT add_compression_policy('trades', INTERVAL '7 days')
    """
  end

  def down do
    drop table(:trades)
  end
end
```

## Schema Design

### Trade Schema with Decimal Types

```elixir
defmodule MyApp.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trades" do
    field :timestamp, :utc_datetime_usec
    field :symbol, :string
    field :side, Ecto.Enum, values: [:buy, :sell]
    field :price, :decimal          # ALWAYS use :decimal for money!
    field :quantity, :decimal
    field :commission, :decimal
    field :user_id, :binary_id
  end

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [:timestamp, :symbol, :side, :price, :quantity, :user_id])
    |> validate_required([:timestamp, :symbol, :side, :price, :quantity])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
  end
end
```

## Query Patterns

### Time-Based Queries

```elixir
# Trades in last hour
from(t in Trade,
  where: t.timestamp > ago(1, "hour"),
  order_by: [desc: t.timestamp]
)
|> Repo.all()

# Daily aggregation
from(t in Trade,
  where: t.timestamp >= ^start_date and t.timestamp < ^end_date,
  group_by: [fragment("date_trunc('day', ?)", t.timestamp), t.symbol],
  select: %{
    day: fragment("date_trunc('day', ?)", t.timestamp),
    symbol: t.symbol,
    volume: sum(t.quantity),
    trades_count: count(t.id),
    avg_price: avg(t.price)
  }
)
|> Repo.all()
```

### Time Buckets

```elixir
# 5-minute candles
query = """
SELECT
  time_bucket('5 minutes', timestamp) AS bucket,
  symbol,
  first(price, timestamp) as open,
  max(price) as high,
  min(price) as low,
  last(price, timestamp) as close,
  sum(quantity) as volume
FROM trades
WHERE symbol = $1
  AND timestamp >= $2
GROUP BY bucket, symbol
ORDER BY bucket DESC
"""

Repo.query(query, ["BTCUSDT", start_time])
```

## Continuous Aggregates

### Creating Materialized Views

```elixir
defmodule MyApp.Repo.Migrations.CreateDailyStats do
  use Ecto.Migration

  def up do
    execute """
    CREATE MATERIALIZED VIEW trades_daily
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('1 day', timestamp) AS day,
      user_id,
      symbol,
      COUNT(*) AS trade_count,
      SUM(CASE WHEN side = 'buy' THEN quantity ELSE 0 END) AS buy_volume,
      SUM(CASE WHEN side = 'sell' THEN quantity ELSE 0 END) AS sell_volume,
      AVG(price) AS avg_price,
      MIN(price) AS min_price,
      MAX(price) AS max_price
    FROM trades
    GROUP BY day, user_id, symbol
    WITH NO DATA
    """

    # Refresh policy - update every hour
    execute """
    SELECT add_continuous_aggregate_policy('trades_daily',
      start_offset => INTERVAL '3 days',
      end_offset => INTERVAL '1 hour',
      schedule_interval => INTERVAL '1 hour'
    )
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS trades_daily CASCADE"
  end
end
```

### Querying Continuous Aggregates

```elixir
def daily_stats(user_id, from_date, to_date) do
  query = """
  SELECT * FROM trades_daily
  WHERE user_id = $1
    AND day >= $2
    AND day < $3
  ORDER BY day DESC
  """
  
  Repo.query(query, [user_id, from_date, to_date])
end
```

## Performance Optimizations

1. **Partitioning**: Auto-partitions by time (chunk_time_interval)
2. **Compression**: Reduces storage by 90%+ for old data
3. **Indexes**: Create on frequently queried columns
4. **Continuous aggregates**: Pre-compute common queries
5. **Retention policies**: Auto-delete old data

### Retention Policy

```elixir
# Delete data older than 90 days
execute """
SELECT add_retention_policy('trades', INTERVAL '90 days')
"""
```

## Best Practices

1. **Use :decimal for all financial data** - NEVER use floats for money
2. **Partition by time** - Use timestamp as first partition key
3. **Compress old data** - Enable compression after data becomes immutable
4. **Use continuous aggregates** - For frequently accessed statistics
5. **Index strategically** - Symbol + timestamp for lookups
6. **Batch inserts** - Use Repo.insert_all for bulk operations

## Common Patterns

### Bulk Insert

```elixir
trades = [
  %{timestamp: ~U[2025-01-01 10:00:00.000000Z], symbol: "BTCUSDT", price: 45000, ...},
  %{timestamp: ~U[2025-01-01 10:00:01.000000Z], symbol: "ETHUSDT", price: 3000, ...}
]

Repo.insert_all(Trade, trades, on_conflict: :nothing)
```

### OHLCV Calculation

```elixir
def calculate_ohlcv(symbol, interval, from, to) do
  interval_sql = case interval do
    "1m" -> "1 minute"
    "5m" -> "5 minutes"
    "1h" -> "1 hour"
    "1d" -> "1 day"
  end

  query = """
  SELECT
    time_bucket($1::interval, timestamp) AS time,
    first(price, timestamp) AS open,
    max(price) AS high,
    min(price) AS low,
    last(price, timestamp) AS close,
    sum(quantity) AS volume
  FROM trades
  WHERE symbol = $2
    AND timestamp >= $3
    AND timestamp < $4
  GROUP BY time
  ORDER BY time
  """

  Repo.query!(query, [interval_sql, symbol, from, to])
end
```
