# Coordit Release Readiness

## Code-owned safeguards

- Fit Lab product imports tolerate late browser-network responses without terminating the API process.
- Fit Lab consumption is backed by the `thread_balances` and `thread_ledger_entries` migration. A valid UUID idempotency key is required for each recommendation request.
- One database RPC locks the balance, persists the fit result and shown-log, records one ledger debit, and returns the remaining balance as one transaction.
- The iOS client no longer decrements the visible production balance before a submission. It hydrates from the server and uses the returned balance after a successful recommendation.
- Shared product links are queued in the App Group instead of overwriting one pending value. The extension only reports success after persistence succeeds.
- Closet registration remains in its loading state until one backend transaction persists both the item and selected size. Failure offers retry instead of a false success page.
- Account deletion is available in the app and deletes the Supabase Auth account; foreign-key cascades remove user-owned application data and the device keychain session is cleared.
- Account deletion only shows completion after it clears in-memory closet state and attempts to erase the deleted user's device-local Fit Lab history directory. A local cleanup failure is surfaced instead of reported as a full success.
- Closet item + selected-size saves require an idempotency key. The atomic SQL function replays the original item and size on retry instead of creating a duplicate.
- A Release build fails closed when `CoorditAPIBaseURL` is missing or not HTTPS. Google sign-in is disabled until both client IDs are present. Rewarded-ad and purchase controls stay disabled until their settlement implementations are complete.

## Required before release

1. Apply all SQL files in `supabase/migrations`, including `20260730_add_thread_wallet.sql`, to the same Supabase project used by the deployed API.
2. Configure a public HTTPS `COORDIT_API_BASE_URL` for the Release build. Do not ship a Release build pointed at localhost.
3. Create the consumable In-App Purchase products in App Store Connect, set immutable product IDs, complete agreements/tax/banking, and configure review metadata.
4. Add StoreKit 2 purchase verification on the deployed backend before enabling an IAP purchase button. Credit a ledger entry with Apple transaction ID idempotency before finishing the transaction.
5. Configure App Store Server Notifications V2 to a deployed HTTPS endpoint and test sandbox notifications.
6. Publish the privacy policy URL, complete App Privacy answers, provide review credentials, and verify the in-app account-deletion workflow against the deployed Supabase project.

## Deliberate non-claims

- This repository cannot prove live App Store billing, server-notification delivery, Apple transaction verification, or a production Supabase migration until owner-controlled Apple/Supabase setup is completed.
- Consumable currency must not be restored from device state; the server ledger is the durable source of truth.
