# OpenRouter Fit Report Design

## Goal

Use `google/gemini-2.5-flash` to write Fit Lab report copy while preserving the
existing deterministic score and size recommendation engine.

## Data Flow

The backend sends only the already-sanitized Fit Report narrative input to
OpenRouter. It requests a strict JSON Schema response, validates that response
at the network boundary, and applies the existing narrative sanitizer before
returning it to iOS. Score calculation, size selection, and yarn consumption do
not depend on the model.

## Privacy and Failure Handling

Every OpenRouter request requires compatible provider parameters, zero data
retention, and data collection denial. If the API key is missing, the provider
does not return a valid schema, or the network call fails, the backend returns
the deterministic fallback report without calling Ollama.

## Verification

The report service test verifies the outgoing schema and provider preferences,
accepts a valid OpenRouter response, and keeps the invalid-response fallback
path covered.
