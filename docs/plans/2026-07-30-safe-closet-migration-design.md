# Safe Closet Save Migration

## Goal

Add idempotent closet saves without interrupting an already deployed backend.

## Design

PostgreSQL supports overloads, so the existing three-argument
`create_clothing_item_with_size` function remains available while the new
four-argument version accepts an idempotency key. The new backend calls the
four-argument function; the old backend continues using the existing one.

## Rollout

1. Apply the migration to create the idempotency request table and new overload.
2. Deploy the backend from the release-readiness PR.
3. Remove the legacy overload only in a future, separately planned cleanup once
   no deployed backend can call it.

## Verification

The migration must contain no `drop function` statement for the legacy
overload, and the existing backend test suite must continue to pass.
