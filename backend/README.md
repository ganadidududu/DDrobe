# coordit Backend

Express + TypeScript REST API for the coordit MVP.

## Commands

```bash
npm install
npm run dev
npm run typecheck
```

## Key Endpoint

`POST /fit/recommend` performs one metered MVP recommendation with Supabase persistence.
It requires a UUID `idempotencyKey`; clients must reuse that key while retrying the same analysis.

`POST /clothing-items/with-size` atomically saves a closet item and its selected measurements.
It also requires a UUID `idempotencyKey` so a retry returns the first saved pair instead of creating duplicates.

`POST /fit-analysis-results/:id/report` builds a fit report from a saved fit result, calls local Ollama, and falls back to a deterministic report if Ollama is unavailable.

`POST /api/v1/products/import-url/preview` analyzes one public product URL without saving it. Setup, API examples, persistence flow, Playwright deployment, and adapter guidance are documented in [`docs/PRODUCT_URL_IMPORT.md`](../docs/PRODUCT_URL_IMPORT.md).

## Ollama Report Env

```bash
OLLAMA_GENERATE_URL=http://localhost:11434/api/generate
OLLAMA_MODEL=llama3.1:8b
```
