# App Review Rejection Remediation Design

## Goal

Resolve the September 1, 2026 App Review rejection for iOS 1.0 (4), upload a verified replacement build, correct the App Privacy answers, reply to App Review, and resubmit the app with its three consumable in-app purchases.

## Observed rejection

- Guideline 2.1(a): after completing Sign in with Apple, reviewers remained on the login screen on iPhone 17 Pro Max and iPad Air 11-inch (M3), iOS 26.6.
- Guideline 5.1.2(i): App Store Connect declared Advertising Data, Device ID, Product Interaction, and Coarse Location as data used to track users, while the app did not request App Tracking Transparency permission.

## Authentication design

Authentication-driven presentation belongs at the root navigation boundary. The root view will observe the authenticated session state and, after a successful transition from signed out to signed in, dismiss the authentication entry. An existing user with completed onboarding returns to the splash and can enter the main app; a new user is presented with onboarding. The provider button callback remains an immediate path, but it is no longer the sole state-transition mechanism.

The fix must not bypass onboarding, fabricate authentication, or hide authentication errors. Failed or cancelled Apple sign-in leaves the user on the authentication screen.

## Privacy design

The submitted release keeps rewarded advertising disabled and does not initialize or request ads. It therefore must not declare the listed data types as being used to track users. App Store Connect privacy answers will be corrected to remove tracking use for Advertising Data, Device ID, Product Interaction, and Coarse Location. ATT will not be added to this release. If rewarded advertising is enabled later, privacy answers and ATT requirements must be reassessed before release.

## Verification and release plan

1. Add a failing UI regression for an authentication session becoming active while the login entry is visible.
2. Apply the smallest root-navigation fix and prove the regression turns green.
3. Run focused authentication tests, the relevant iOS UI suite, and an unsigned Release build for iPhone/iPad compatibility.
4. Increment to build 5, archive, validate, and upload.
5. Correct App Privacy answers, update review notes with the exact fix and validation path, reply to the rejection, and resubmit Build 5 with all three IAPs.

## Safety boundaries

- No change to IAP product identifiers, pricing, wallet settlement, backend deployment, or database schema.
- No ATT prompt unless the app actually performs tracking.
- Do not resubmit until the new build finishes App Store processing and the privacy changes are published.
