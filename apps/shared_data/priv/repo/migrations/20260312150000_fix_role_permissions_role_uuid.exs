defmodule Ecto.Migrations.FixRolePermissionsRoleUuid do
  @moduledoc """
  Adds missing `role_uuid` column to `phoenix_kit_role_permissions`.

  V56 (run as part of the V44->V60 migration) calls UUIDFKColumns.up/1 which
  should have added this column. It was silently skipped — likely because
  `role_id` was not yet visible to information_schema within the same transaction
  when the V53 table creation and V56 column addition ran together.

  By V78, the legacy integer FK columns (role_id) were already dropped, so
  no backfill from role_id is possible or needed. The table has no existing rows
  in practice (permissions are seeded at startup), so no backfill is required.
  """

  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # 1. Add role_uuid column if missing (may already exist from a partial run)
    execute("""
    ALTER TABLE public.phoenix_kit_role_permissions
    ADD COLUMN IF NOT EXISTS role_uuid UUID
    """)

    # 2. Delete orphaned rows that have no role_uuid (cannot be backfilled —
    #    legacy role_id column was already dropped). Permissions are re-seeded
    #    at startup so no data is lost.
    execute("""
    DELETE FROM public.phoenix_kit_role_permissions
    WHERE role_uuid IS NULL
    """)

    # 3. Set NOT NULL
    execute("""
    ALTER TABLE public.phoenix_kit_role_permissions
    ALTER COLUMN role_uuid SET NOT NULL
    """)

    # 4. Add FK index for role_uuid
    execute("""
    CREATE INDEX IF NOT EXISTS phoenix_kit_role_permissions_role_uuid_idx
    ON public.phoenix_kit_role_permissions(role_uuid)
    """)

    # 5. Add unique index for ON CONFLICT ("role_uuid","module_key")
    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_role_permissions_role_uuid_module_key_idx
    ON public.phoenix_kit_role_permissions(role_uuid, module_key)
    """)

    # 5. Add FK constraint to phoenix_kit_user_roles(uuid)
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_role_permissions_role_uuid'
        AND conrelid = 'public.phoenix_kit_role_permissions'::regclass
      ) THEN
        ALTER TABLE public.phoenix_kit_role_permissions
        ADD CONSTRAINT fk_role_permissions_role_uuid
        FOREIGN KEY (role_uuid)
        REFERENCES public.phoenix_kit_user_roles(uuid)
        ON DELETE CASCADE;
      END IF;
    END $$;
    """)
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_role_permissions_role_uuid'
        AND conrelid = 'public.phoenix_kit_role_permissions'::regclass
      ) THEN
        ALTER TABLE public.phoenix_kit_role_permissions
        DROP CONSTRAINT fk_role_permissions_role_uuid;
      END IF;
    END $$;
    """)

    execute("DROP INDEX IF EXISTS phoenix_kit_role_permissions_role_uuid_module_key_idx")
    execute("DROP INDEX IF EXISTS phoenix_kit_role_permissions_role_uuid_idx")

    execute("""
    ALTER TABLE public.phoenix_kit_role_permissions
    DROP COLUMN IF EXISTS role_uuid
    """)
  end
end
