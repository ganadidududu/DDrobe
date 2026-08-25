# Styling-Only Forward Repair

**Status:** Approved 2026-08-25

## Goal

Complete styling persistence from the newly observed production-like catalog
without modifying the already exact `public.users.birth_date` column, replaying
historical migrations, or creating a Supabase migration ledger.

## Exact live precondition

The only mutable starting state accepted by the repair is all of the following:

- `supabase_migrations.schema_migrations` is absent.
- `public.coordit_schema_change_records` has the exact committed release shape.
- The committed `20260822_reconcile_monetization_release_schema.sql` receipt is
  present with its exact filename and SHA-256.
- `public.users.id` remains the exact UUID primary-key prerequisite.
- `public.users.birth_date` already exists as an ordinary, nullable `date`
  column with no default.
- `public.styling_looks` is absent.
- No receipt exists for either the superseded `20260824` profile/styling repair
  or the new `20260825` styling-only repair.

Any one-sided, partially created, incorrectly typed, incorrectly secured, or
conflicting receipt state is catalog drift and must fail before DDL or durable
DML.

## Chosen approach

Keep `20260824_reconcile_profile_styling_schema.sql` and its operator surface
immutable. Add a new `20260825_finalize_styling_schema.sql` migration with a
dedicated typed runner, CLI, postflight, connection-only probe, package scripts,
and test harness.

This is preferred over changing the 20260824 artifact because its filename and
SHA identify a reviewed but now inapplicable contract. It is also preferred
over a configurable multi-migration runner because a dedicated approval token,
advisory lock, GUC namespace, and receipt schema make accidental cross-version
execution unrepresentable.

The new CLI reuses
`monetization-schema-reconciliation.operator-pg-client.ts` for verified TLS. It
does not duplicate or weaken CA parsing or `rejectUnauthorized` behavior.

## Transaction and state machine

The runner requires an exact 20260825 approval token, reads and hashes the
checked-in migration, then performs one `BEGIN`/`COMMIT` transaction. Inside the
transaction it:

1. Sets local lock timeout to five seconds and statement timeout to 30 seconds.
2. Takes a fixed 20260825 advisory transaction lock.
3. Sets transaction-local filename, SHA-256, and lock-acquired GUCs.
4. Executes the migration.
5. Runs a fixed read-only typed postflight.
6. Reads and parses the exact 20260825 durable change record.

Every failure rolls back the complete transaction.

The migration accepts exactly two states:

1. **Observed live state:** the exact precondition above. It creates the styling
   objects and records `reconciled_observed_partial` for version 20260825.
2. **Exact replay:** `birth_date` and the complete styling target are exact, the
   20260824 receipt remains absent, and the exact 20260825 filename/SHA receipt
   with `reconciled_observed_partial` already exists. It performs no DDL and
   preserves the original receipt.

An exact styling catalog without the exact 20260825 receipt is not replay and
is rejected. The migration never records `verified_exact_target` because that
unobserved adoption path is outside the approved state machine.

## Schema effects

The only catalog creation is `public.styling_looks` with the existing reviewed
11-column shape, UUID primary key, `users(id)` cascading foreign key, and
`styling_looks_user_id_idx` B-tree index. The migration enables RLS, creates no
policies, revokes all table privileges from `public`, `anon`, `authenticated`,
and `service_role`, then grants only select/insert/update/delete to
`service_role`.

The only durable DML is the single 20260825 row in the existing change-record
table. The migration performs no `ALTER TABLE public.users` and no DML against
existing user, wallet, ledger, or styling rows.

## Verification

Tests use disposable embedded PostgreSQL initialized to the production-like
state: exact monetary reconciliation followed by an exact pre-existing
`birth_date`. They must prove:

- the live shape is unsupported before the 20260825 artifacts exist (semantic
  RED), then applies successfully and replays exactly;
- `birth_date` metadata and sentinel values are unchanged;
- only `styling_looks` and the 20260825 change record are added;
- the exact columns, generated-column status, FK, index, RLS, policies, and
  privileges match the contract;
- absent/wrong `birth_date`, partial or wrong styling shapes, generated columns,
  either conflicting repair receipt, an unrecorded exact target, a missing or
  mismatched monetary receipt, and a Supabase ledger all fail before mutation;
- invalid approval or CA inputs fail before TCP connection;
- the scope-specific probe performs only connect/end and redacts failures;
- forced postflight failure rolls back the styling table and receipt while
  preserving the pre-existing birth column and all sentinel rows.

Focused database suites run repeatedly, followed by typecheck and the complete
backend test suite. The production runbook pins the finalized migration SHA and
identifies the 20260825 CLI as the only applicable styling repair procedure.
