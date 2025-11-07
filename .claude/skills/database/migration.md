---
name: db-migration
description: Generate Ecto migration with common patterns and TimescaleDB support
tags: database, ecto, migration, postgresql, timescaledb
---

# Generate Database Migration

This skill helps create Ecto migrations with common patterns and TimescaleDB support.

## Step 1: Choose Migration Type

Ask the user to select:
1. **Create table** - new database table
2. **Alter table** - modify existing table
3. **Add column** - add new column to existing table
4. **Add index** - create database index
5. **Create hypertable** - TimescaleDB hypertable for time-series data
6. **Add foreign key** - create relationship between tables

## Step 2: Generate Migration File

```bash
# Generate migration file
mix ecto.gen.migration {migration_name}
```

This creates: `priv/repo/migrations/{timestamp}_{migration_name}.exs`

## Migration Templates

### Template 1: Create Table

```elixir
defmodule SharedData.Repo.Migrations.Create{TableName} do
  use Ecto.Migration

  def change do
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "pending", null: false
      add :amount, :decimal, precision: 20, scale: 8
      add :metadata, :map, default: %{}
      add :settings, :jsonb

      # Foreign keys
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    # Indexes
    create index(:{table_name}, [:user_id])
    create index(:{table_name}, [:status])
    create index(:{table_name}, [:inserted_at])
    create unique_index(:{table_name}, [:name], name: :{table_name}_name_unique)

    # Composite indexes
    create index(:{table_name}, [:user_id, :status])

    # Partial indexes
    create index(:{table_name}, [:user_id], where: "status = 'active'")
  end
end
```

### Template 2: Create TimescaleDB Hypertable

```elixir
defmodule SharedData.Repo.Migrations.Create{TableName}Hypertable do
  use Ecto.Migration

  def up do
    # Create table
    create table(:{table_name}, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :symbol, :string, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :volume, :decimal, precision: 20, scale: 8, null: false
      add :data, :jsonb

      timestamps(updated_at: false)
    end

    # Create hypertable (TimescaleDB)
    execute """
    SELECT create_hypertable(
      '{table_name}',
      'timestamp',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    );
    """

    # Create indexes
    create index(:{table_name}, [:timestamp, :symbol])
    create index(:{table_name}, [:symbol, :timestamp])

    # Optional: Create continuous aggregate
    execute """
    CREATE MATERIALIZED VIEW {table_name}_1min
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('1 minute', timestamp) AS bucket,
      symbol,
      first(price, timestamp) AS open,
      max(price) AS high,
      min(price) AS low,
      last(price, timestamp) AS close,
      sum(volume) AS volume
    FROM {table_name}
    GROUP BY bucket, symbol;
    """

    # Enable compression (optional)
    execute """
    ALTER TABLE {table_name} SET (
      timescaledb.compress,
      timescaledb.compress_segmentby = 'symbol',
      timescaledb.compress_orderby = 'timestamp DESC'
    );
    """

    # Set compression policy (compress data older than 7 days)
    execute """
    SELECT add_compression_policy('{table_name}', INTERVAL '7 days');
    """

    # Set retention policy (drop data older than 90 days)
    execute """
    SELECT add_retention_policy('{table_name}', INTERVAL '90 days');
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS {table_name}_1min CASCADE;"
    drop table(:{table_name})
  end
end
```

### Template 3: Alter Table

```elixir
defmodule SharedData.Repo.Migrations.Alter{TableName} do
  use Ecto.Migration

  def change do
    alter table(:{table_name}) do
      # Add columns
      add :new_field, :string
      add :active, :boolean, default: true

      # Modify columns
      modify :status, :string, from: :integer
      modify :amount, :decimal, precision: 30, scale: 10

      # Remove columns
      remove :old_field
    end

    # Add new indexes
    create index(:{table_name}, [:new_field])
  end
end
```

### Template 4: Add Index

```elixir
defmodule SharedData.Repo.Migrations.AddIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Regular index
    create index(:{table_name}, [:field_name])

    # Unique index
    create unique_index(:{table_name}, [:email])

    # Composite index
    create index(:{table_name}, [:user_id, :created_at])

    # Concurrent index (no table lock)
    create index(:{table_name}, [:field], concurrently: true)

    # Partial index
    create index(:{table_name}, [:status], where: "deleted_at IS NULL")

    # GIN index for JSONB
    create index(:{table_name}, [:metadata], using: :gin)

    # GiST index for full-text search
    execute """
    CREATE INDEX {table_name}_search_idx ON {table_name}
    USING GiST (to_tsvector('english', name || ' ' || description));
    """
  end
end
```

### Template 5: Add Foreign Key

```elixir
defmodule SharedData.Repo.Migrations.AddForeignKeys do
  use Ecto.Migration

  def change do
    alter table(:{table_name}) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    create index(:{table_name}, [:user_id])

    # Or add FK to existing column
    execute "ALTER TABLE {table_name} ADD CONSTRAINT {table_name}_user_id_fkey
             FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE"
  end
end
```

### Template 6: Add Triggers

```elixir
defmodule SharedData.Repo.Migrations.AddTriggers do
  use Ecto.Migration

  def up do
    # Auto-update updated_at timestamp
    execute """
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER update_{table_name}_updated_at
    BEFORE UPDATE ON {table_name}
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
    """

    # Audit log trigger
    execute """
    CREATE TRIGGER {table_name}_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON {table_name}
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS update_{table_name}_updated_at ON {table_name};"
    execute "DROP TRIGGER IF EXISTS {table_name}_audit_trigger ON {table_name};"
    execute "DROP FUNCTION IF EXISTS update_updated_at_column();"
  end
end
```

## Step 3: Run Migration

```bash
# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Rollback to specific version
mix ecto.rollback --to 20231107120000

# Check migration status
mix ecto.migrations
```

## Best Practices

### 1. Use Reversible Migrations

```elixir
def change do
  # This is automatically reversible
  create table(:users)
end

# For complex changes, use up/down
def up do
  execute "CREATE INDEX CONCURRENTLY ..."
end

def down do
  execute "DROP INDEX ..."
end
```

### 2. Handle Large Tables Safely

```elixir
# Disable locks for large tables
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  create index(:large_table, [:field], concurrently: true)
end
```

### 3. Use Check Constraints

```elixir
def change do
  create table(:orders) do
    add :amount, :decimal
    add :status, :string
  end

  create constraint(:orders, :amount_must_be_positive, check: "amount > 0")
  create constraint(:orders, :valid_status,
    check: "status IN ('pending', 'completed', 'cancelled')")
end
```

### 4. Add Comments

```elixir
def change do
  create table(:users) do
    add :email, :string
  end

  execute "COMMENT ON TABLE users IS 'User accounts';"
  execute "COMMENT ON COLUMN users.email IS 'User email address (unique)';"
end
```

### 5. Handle Enum Types

```elixir
def up do
  execute """
  CREATE TYPE user_role AS ENUM ('admin', 'user', 'moderator');
  """

  alter table(:users) do
    add :role, :user_role, default: "user"
  end
end

def down do
  alter table(:users) do
    remove :role
  end

  execute "DROP TYPE user_role;"
end
```

## Common Patterns

### UUID Primary Keys

```elixir
create table(:items, primary_key: false) do
  add :id, :binary_id, primary_key: true
  # OR use UUID v7 (timestamp-based)
  # add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
end
```

### Soft Delete

```elixir
create table(:items) do
  add :deleted_at, :utc_datetime
end

create index(:items, [:deleted_at])
```

### Polymorphic Associations

```elixir
create table(:comments) do
  add :commentable_type, :string
  add :commentable_id, :binary_id
  add :content, :text
end

create index(:comments, [:commentable_type, :commentable_id])
```

## Testing Migrations

```elixir
# In test file
test "migration creates table" do
  assert :ok = Ecto.Migrator.up(Repo, version, YourMigration)

  # Verify table exists
  assert {:ok, _} = Repo.query("SELECT * FROM your_table LIMIT 1")

  # Test rollback
  assert :ok = Ecto.Migrator.down(Repo, version, YourMigration)
end
```
