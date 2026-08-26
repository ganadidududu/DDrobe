# Persistent social session and signup yarn design

## Goal

After a successful Google or Apple signup, keep the user signed in across app launches. Returning users see the existing splash and enter the product by tapping the screen instead of seeing signup again. Newly created users receive exactly three yarn; existing balances never change.

## Authentication design

- Keep the complete backend session in the existing iOS Keychain store.
- Add a backend refresh endpoint that exchanges the stored Supabase refresh token for a new access/refresh token pair.
- On cold launch, load the Keychain record immediately so the splash renders as a returning-user surface, then refresh the session in the background before protected data is loaded.
- Save refreshed tokens atomically. Never delete a working Keychain record before its replacement is persisted.
- Treat an explicit permanent authentication rejection as session invalidation. Delete local credentials only for that case, logout, or account deletion.
- Preserve credentials for connectivity, timeout, server, and decoding failures so a temporary outage cannot turn a returning user into a signup user.
- The returning splash remains tap-to-enter. It does not automatically navigate and it never opens the provider sheet by itself.

## Initial yarn design

- Add a forward-only database migration.
- Change the wallet default for future rows to three.
- Add an idempotent user-insert trigger that creates a three-yarn wallet exactly once when a new public user profile is inserted.
- Existing wallet rows and balances are untouched.
- Repeated Google/Apple login and profile upsert cannot grant yarn again.

## Error handling

- Refresh success replaces the Keychain session and continues normal bootstrap.
- Permanent refresh rejection clears the invalid session and returns to the authentication entry.
- Transient refresh failure keeps the session and returning splash; protected requests may retry on the next foreground/bootstrap cycle.
- Wallet provisioning uses `insert ... on conflict do nothing`, so retries and concurrent auth callbacks remain exactly once.

## Verification

- Backend RED/GREEN tests for refresh success, rejection, malformed input, and profile preservation.
- iOS RED/GREEN tests for Keychain restoration, atomic replacement, transient-failure preservation, permanent-rejection deletion, and tap-to-enter routing.
- Embedded PostgreSQL migration tests proving new user equals three, repeated login remains three, existing balances remain unchanged, and rollback leaves no partial state.
- Simulator QA: authenticate fixture, terminate and relaunch, verify no signup button, tap splash, and reach the main screen.
- Full backend tests, iOS build/tests, clean diff, and secret scan before commit/deploy.

## Execution plan

1. Capture failing session-refresh and three-yarn tests.
2. Implement the backend refresh contract and forward wallet migration.
3. Implement iOS refresh/bootstrap and atomic Keychain replacement.
4. Run focused and full automated gates.
5. Run simulator cold-launch QA and record evidence.
6. Commit the implementation separately from this design, deploy the backend and migration with flags unchanged, then verify health and a real relaunch.
