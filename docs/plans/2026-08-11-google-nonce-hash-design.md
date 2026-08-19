# Google ID-token nonce validation design

## Goal

Resolve the Google sign-in error reporting that the supplied nonce and the ID-token nonce do not satisfy Supabase validation.

## Options considered

1. Omit the nonce from the backend request. Rejected: Google may still include a nonce claim and Supabase will reject the one-sided value; it also weakens replay protection.
2. Disable nonce validation. Rejected: this removes a security control and is unsuitable for production.
3. Hash only the nonce given to Google and retain the raw nonce for Supabase. Chosen: this matches the Supabase native Google sign-in contract.

## Approved flow

1. Generate a unique raw nonce in the iOS Google sign-in helper.
2. Compute its SHA-256 digest as lowercase hexadecimal.
3. Give the hash to `GIDSignIn` so it is embedded in the returned Google ID token.
4. Keep the raw nonce in `CoorditGoogleSignInCredential` and forward it through the existing client and backend path.
5. Supabase hashes that raw nonce and validates it against the ID token claim.

## Scope and safeguards

- Only the iOS Google sign-in helper changes; Apple Sign In and the backend API remain unchanged.
- Add focused tests for raw-versus-hashed nonce behavior and deterministic SHA-256 encoding.
- Build, run focused tests, install the Debug build on the connected iPhone, and have the Google sign-in flow exercised manually because it requires the user’s Google account interaction.
