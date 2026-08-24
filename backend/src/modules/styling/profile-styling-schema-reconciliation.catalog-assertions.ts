import assert from "node:assert/strict";
import type { Client } from "pg";
import {
  readStylingColumns,
  readStylingConstraints,
  readStylingIndexes,
  readStylingSecurity
} from "./profile-styling-schema-reconciliation.db-assertions";

export const assertExactProfileStylingCatalog = async (client: Client): Promise<void> => {
  assert.deepEqual(await readStylingColumns(client), [
    {
      column_name: "id",
      data_type: "uuid",
      is_nullable: "NO",
      column_default: "gen_random_uuid()",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "user_id",
      data_type: "uuid",
      is_nullable: "NO",
      column_default: null,
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "name",
      data_type: "text",
      is_nullable: "NO",
      column_default: null,
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "name_ko",
      data_type: "text",
      is_nullable: "NO",
      column_default: null,
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "mood",
      data_type: "text",
      is_nullable: "NO",
      column_default: "''::text",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "palette",
      data_type: "jsonb",
      is_nullable: "NO",
      column_default: "'[]'::jsonb",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "ai_reasoning",
      data_type: "text",
      is_nullable: "NO",
      column_default: "''::text",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "fit_score",
      data_type: "numeric",
      is_nullable: "YES",
      column_default: null,
      numeric_precision: 5,
      numeric_scale: 2
    },
    {
      column_name: "item_ids",
      data_type: "jsonb",
      is_nullable: "NO",
      column_default: "'[]'::jsonb",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "prompt",
      data_type: "text",
      is_nullable: "NO",
      column_default: "''::text",
      numeric_precision: null,
      numeric_scale: null
    },
    {
      column_name: "created_at",
      data_type: "timestamp with time zone",
      is_nullable: "NO",
      column_default: "now()",
      numeric_precision: null,
      numeric_scale: null
    }
  ]);
  assert.deepEqual(await readStylingConstraints(client), [
    { name: "styling_looks_pkey", definition: "PRIMARY KEY (id)" },
    {
      name: "styling_looks_user_id_fkey",
      definition: "FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE"
    }
  ]);
  assert.deepEqual(await readStylingIndexes(client), [
    {
      name: "styling_looks_pkey",
      definition:
        "CREATE UNIQUE INDEX styling_looks_pkey ON public.styling_looks USING btree (id)"
    },
    {
      name: "styling_looks_user_id_idx",
      definition:
        "CREATE INDEX styling_looks_user_id_idx ON public.styling_looks USING btree (user_id)"
    }
  ]);
  assert.deepEqual(await readStylingSecurity(client), {
    rls_enabled: true,
    force_rls: false,
    policy_count: 0,
    service_select: true,
    service_insert: true,
    service_update: true,
    service_delete: true,
    service_extra: false,
    anon_access: false,
    authenticated_access: false
  });
};
