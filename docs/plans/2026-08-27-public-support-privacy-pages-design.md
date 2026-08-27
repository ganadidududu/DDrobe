# Public support and privacy pages

## Goal

Publish stable, unauthenticated COORDIT support and privacy-policy pages on the existing Cloud Run service so App Store Connect can reference them.

## Chosen design

Add two read-only Express routes to the existing backend:

- `GET /support` provides the support email, common support topics, and account-deletion guidance.
- `GET /privacy` describes the app's collected data, purposes, processors, retention, user rights, and contact channel.

Both routes return self-contained Korean HTML with accessible landmarks, responsive CSS, UTF-8 content, and no scripts, cookies, forms, authentication, database calls, or feature-flag dependencies. The privacy page links back to support, and the support page links to the privacy policy.

## Alternatives considered

1. A separate static host would isolate marketing content, but would add a new domain, deployment surface, and DNS ownership proof.
2. App Store Connect-only text would not provide the public URLs Apple requires.
3. Existing Cloud Run routes reuse the already deployed HTTPS domain and are the smallest reversible change, so this is the selected approach.

## Verification and rollout

Lock both HTTP contracts with real-server tests before implementation. Then run backend typecheck, focused tests, full tests, and build. Deploy the immutable backend candidate without traffic, verify both tagged pages and health, inspect bounded logs, then move traffic while preserving environment variables, secrets, tags, runtime settings, and disabled monetization flags. Finally save the stable URLs in App Store Connect.

## Non-goals

This change does not enable IAP or rewarded ads, alter authentication, access user data, modify the database, submit the app for review, or create a new domain.
