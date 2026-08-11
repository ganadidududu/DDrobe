# Auth Gate and App Icon Design

**Status:** Approved 2026-08-11

## Goal

Ship a reviewable iOS change that restores the Coordit app icon and prevents an unauthenticated user from entering app content or seeing a thread balance.

## User-facing behavior

### First installation

- The splash screen remains visible.
- The existing `로그인/회원가입` button opens the existing Google/Apple authentication sheet.

### Returning user without a session

- When the welcome flow was completed previously but there is no stored session, the app remains on the splash screen and presents the same authentication sheet automatically.
- Dismissing the sheet leaves the user on the splash screen; it never reveals app content.
- Logging out returns the user to this gated splash state.

### Authenticated user

- Existing returning-user splash behavior and the route into the app remain unchanged.
- Thread balance is fetched only after a session exists.

### Thread privacy

- The production default balance is zero rather than a demo value.
- The root gate prevents every content route, including the thread charge screen, from rendering without a session. Therefore no balance amount is visible to a logged-out user.

## Implementation

- Add a `hasCompletedWelcome` / auto-auth decision to `CoorditWelcomeLaunchState`.
- In `CoorditRootView`, observe the authentication state. On loss of a session, reset ephemeral thread state, route to splash, and show the authentication sheet for returning users. Do not render any non-splash route while unauthenticated.
- Preserve the existing splash button for first installs.
- Add regression tests for launch-state decisions and UI tests for first-install versus returning-logged-out presentation.
- Copy the approved image into all required AppIcon idioms and commit the asset catalog manifest with those files.
- Include the two compile corrections that surfaced during the device build: import Combine for the rewarded-ad observable service, and make the two parent-owned thread-charge state properties available to their extension file.

## Google sign-in boundary

Live reproduction shows the deployed Cloud Run service returns `401 {\"message\":\"fetch failed\"}` for `POST /auth/google`, while the same request to the local backend returns `401 {\"message\":\"Bad ID token\"}`. The source route is identical, so the remaining fault is the owner-controlled Cloud Run Supabase environment/egress configuration, not the iOS Google test-user list.

This PR will document the observed deployment blocker in its description. The Cloud Run service must bind the correct `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets and deploy a new revision before live Google sign-in can succeed.

## Verification

- Build and run the iOS app on the simulator.
- Verify first-install, returning-logged-out, and authenticated fixtures with UI tests and fresh screenshots.
- Build, install, and launch the Debug app on the connected iPhone.
- Verify the compiled AppIcon asset set is present in the installed product.
- Verify backend Google login behavior with the existing staging invalid-token probe; successful Cloud Run configuration changes this response from `fetch failed` to an identity-token validation error.
