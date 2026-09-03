# Guest DeviceCheck Authentication Design

## Goal

Allow people to use COORDIT without an Apple or Google login while preserving the existing device-level three-thread welcome grant, server-backed Fit Lab execution, and later account continuity. Fix Sign in with Apple so an authenticated user leaves the login sheet immediately even if post-login profile synchronization fails.

## Chosen approach

Use a Supabase anonymous auth user as the guest's server identity. Existing user-owned tables, authorization middleware, Fit Lab persistence, and thread-wallet operations continue to use a Supabase user UUID. DeviceCheck records whether the physical device has already received the welcome grant. When the guest later signs in with Apple or Google, a new social identity is linked directly to that UUID. If the identity already belongs to a member, the backend migrates guest-owned records and the remaining balance to the permanent account in one database transaction.

Separate guest tables were rejected because they duplicate most user-owned storage and service behavior. A local-only guest was rejected because Fit Lab and its wallet are server-backed and because reinstall continuity would be unreliable.

## Authentication states

The client distinguishes three states:

- `bootstrapping`: restoring an existing session or requesting a guest session.
- `guest`: an anonymous Supabase session that can call the normal authenticated backend routes.
- `member`: an Apple, Google, or email-backed Supabase session.

The existing first-screen `로그인/회원가입` action opens a start chooser containing Google, Apple, and `비회원으로 로그인하기`. Guest access therefore remains available without completing social authentication while preserving the approved splash hierarchy. Login remains optional for synchronization and account recovery.

## Guest bootstrap and welcome grant

1. The app requests a public guest-session endpoint.
2. The backend creates a Supabase anonymous user and a corresponding `public.users` row with an internal non-personal placeholder email.
3. The app persists that session before requesting a DeviceCheck token.
4. The app submits the DeviceCheck token to an authenticated welcome-claim endpoint, which queries Apple's server API.
5. If the device has not received the promotion, the backend creates a three-thread wallet grant and sets the DeviceCheck promotion bit.
6. If the bit is already set, the guest session is created without another welcome grant.
7. The endpoint returns a normal COORDIT auth session, which the client stores and uses for existing authenticated routes.

The database wallet default must not implicitly create promotional balance. Welcome threads are issued only through an idempotent ledger-backed grant operation.

If DeviceCheck is temporarily unavailable, the backend must not mint an untracked welcome grant. It returns a retryable bootstrap error while the client retains any existing session. Review and automated tests use injected DeviceCheck adapters rather than production Apple services.

## Account upgrade and migration

Apple and Google login requests may include the current guest bearer token and refresh token. When the social identity is new, Supabase links it directly to the anonymous user, preserving the same UUID and all existing data without migration.

When the social identity already belongs to a permanent account, the backend authenticates that destination and runs a single migration transaction that:

- locks the guest and destination wallets;
- transfers the remaining guest balance without duplicating prior grants;
- reassigns guest-owned closet, measurement, product, reference, Fit Lab, report, feedback, and related records to the destination user;
- resolves uniqueness conflicts deterministically;
- records the migration idempotency key;
- removes the disposable guest profile after all transfers succeed.

If migration fails, the social login request fails without altering the guest session or guest data. Repeating the request is safe. Only identities that already belong to permanent accounts require this migration path.

## Sign in with Apple completion

Authentication completion is separated from account hydration:

1. Receive a valid social auth session.
2. Persist the token and publish the session immediately.
3. Close the authentication sheet based on the published authenticated/member state.
4. Refresh profile, measurements, closet, and balance afterward.
5. Surface hydration failures as a recoverable synchronization warning without returning the user to the login screen.

This removes the current coupling where a profile or measurement request can prevent the already-authenticated session from becoming visible to SwiftUI.

## Security and privacy

- DeviceCheck is used only to answer whether the device already received the welcome promotion.
- App Attest may protect sensitive guest bootstrap and Fit Lab requests, but it is complementary because its keys do not survive reinstall.
- DeviceCheck private keys remain in backend deployment secrets and never ship in the app.
- Guest placeholder emails are internal identifiers and are never shown as user contact information.
- Migration authorization requires both a valid guest bearer token and a successfully authenticated destination identity.

## Tests

- A fresh DeviceCheck state grants exactly three threads.
- A previously claimed device creates a guest with zero new promotional threads.
- Repeating guest bootstrap or migration is idempotent.
- A guest can run Fit Lab through the existing authenticated routes.
- Guest closet, analyses, and remaining threads move to a new member account.
- The same data moves safely into an existing member account.
- A failed migration preserves the guest session and all guest data.
- Apple login publishes the member session before profile hydration.
- Profile or measurement hydration failure does not keep the authentication sheet open.
- Clean-install UI coverage verifies the three-choice start sheet, entry as guest, retryable guest failure, and successful Apple login transition.

## Deployment requirements

The backend needs the Apple DeviceCheck key ID, team ID, and private `.p8` key in its secret environment. Supabase anonymous sign-ins must be enabled. The database migration and backend deployment must complete before distributing the matching iOS build.
