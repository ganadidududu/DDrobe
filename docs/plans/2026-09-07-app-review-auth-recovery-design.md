# App Review authentication recovery design

## Goal

Ensure App Review and normal users can always enter COORDIT through guest access, while preserving DeviceCheck-based welcome-credit abuse protection and providing a conventional reviewer account fallback.

## Authentication entry

The existing chooser keeps Google, Apple, and guest access. It adds a normal email-login path that opens a compact email/password form. This is a production authentication path backed by the existing `/auth/login` endpoint, not a hidden bypass or hardcoded credential.

App Review receives credentials for a dedicated Supabase reviewer account through App Store Connect Review Information. Credentials never appear in source control, the app bundle, logs, screenshots, or documentation committed to the repository.

## Guest flow

Anonymous session creation is the authentication boundary. Once `/auth/guest` succeeds and the session is persisted, the sheet closes and the user enters the app. DeviceCheck and `/auth/guest/welcome` remain responsible for the one-time three-thread grant, but a failure in that secondary operation cannot invalidate or hide an already-created guest session. The app reports that the welcome balance is still being checked and retries safely through the server's idempotent claim state.

## Apple flow

The native Sign in with Apple result continues to be exchanged through `/auth/apple`. The fix must preserve guest-account linking and existing data. Production Supabase Apple provider configuration, nonce handling, bundle identity, and the backend's guest-upgrade inputs are verified against the actual failing request before any code or cloud setting is changed.

## Error handling and observability

Authentication failures remain user-visible and retryable. Welcome-credit failures are classified separately from authentication failures. Server logs record safe error categories, request paths, and provider status without identity tokens, refresh tokens, credentials, or DeviceCheck tokens.

## Verification

- All simulator discovery, boot, and slimming uses SimSlim. Before build or launch, apply and verify `config/simslim/coordit-dev.json`, then run the required capability doctor checks.
- Failing-first regression test: a successful guest session followed by a failed welcome claim still enters the app and persists the session.
- Guest flow on a freshly installed iPad-sized simulator and a physical iPhone.
- Relaunch restores the same guest account and balance.
- Apple login succeeds from both a fresh install and an existing guest session.
- Reviewer email credentials sign in from the first authentication sheet.
- App Store Connect Review Information contains the credentials and concise test steps.
