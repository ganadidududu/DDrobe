# Fit Lab Gemini 2.5 fallback repair

## Goal

Fit Lab should use the configured OpenRouter model `google/gemini-2.5-flash` and persist `source=openrouter` when the provider returns an acceptable report. Provider or validation failures must continue to return the deterministic fallback report so users are not blocked.

## Chosen approach

Keep fallback behavior, add a privacy-safe failure classification at the Fit Report boundary, and make the smallest provider/request or response-parser correction justified by runtime evidence. Do not expose prompts, report text, user identifiers, API keys, provider payloads, or raw provider errors.

Alternatives rejected:

- Return an error to the app: clearer failure, but degrades the existing resilient user experience.
- Roll back to another model: fast, but contradicts the required Gemini 2.5 configuration and hides the compatibility defect.

## Data flow

1. Fit Lab consumes one thread and builds the existing v6 prompt.
2. The backend calls the configured OpenRouter model.
3. The response crosses the existing Zod boundary and narrative acceptance check.
4. Accepted output is persisted with `source=openrouter`; any classified failure persists the existing deterministic fallback.
5. Operational logs contain only a stable failure category and configured model name.

## Error handling

Distinguish provider HTTP failure, timeout, provider response-shape failure, generated-report JSON failure, and narrative rejection. Unknown errors remain fail-safe and must not leak raw messages or request content.

## Verification

- Capture the current failure category from logged-in OpenRouter activity or a safe production diagnostic.
- Add a failing-first regression fixture matching the observed provider behavior.
- Apply the minimal fix and run focused Fit Report tests, typecheck, full backend tests, and a candidate deployment health/log gate.
- Perform one real Fit Lab generation and verify the newest stored artifact has `source=openrouter`, exact Gemini 2.5 model, and prompt version v6.

## Deployment safety

Deploy an immutable candidate revision with no traffic, verify health and logs, promote once, retain the current revision for rollback, and keep AdMob/IAP flags disabled.
