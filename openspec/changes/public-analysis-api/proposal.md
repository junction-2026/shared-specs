# Simple public analysis API for platforms and outlets (junction-2026/project#100)

## Why
Social media platforms and news outlets want to send a post, one or more comments, or both, and get the analysis
back as JSON without logging in, without an API key and without parsing raw analyzer blobs. Today the only way is
`POST /api/v1/jobs` plus reading the full Job object, whose analyzer results are nested per analyzer and need
knowledge of several result capabilities to interpret.

## What changes
- New shared capability `public-analysis-api` (additive), two endpoints under `/api/v1/public`:
  - `POST /api/v1/public/analyses` accepts `post` (or its alias `text`), `comments` (string or array of strings),
    both together, or `url` instead of pasted text. It creates **one** ordinary analysis job through the existing
    pipeline (same as the UI: all analyzers, `options.finalize: true`), composing several texts into one
    `input.content` with `Post:` / `Comment <n>:` separators. Responds 201 with a PublicAnalysis object.
  - `GET /api/v1/public/analyses/{id}` returns the PublicAnalysis of any job id: `id`, `status`, `done`,
    `coverage` while running; when done, `result` (`verdict`, `confidence`, `user_text`, `produced_by`) plus
    flattened summaries of techniques, the text-origin (bot) signal, fact checks, news coverage and Wikipedia
    lookups, and a `share_url` to the web result page when the deployment configures its public base URL.
  - Error codes: 400 `invalid_request` (empty or malformed body), 400 `missing_content` (no post, text, comment or
    url), 422 `validation_failed` (wrong member types, conflicting members, too many comments, bad url),
    413 `payload_too_large`, 404 `not_found`, 503 `scrape_unavailable`, 429 `rate_limited`.
  - A global (not per-client) request rate limit per endpoint, deployment-configurable, answering 429
    `rate_limited` with `Retry-After` and `error.details.retry_after_s` like analysis-chat-api.
  - No authentication of any kind on these endpoints.
- Jobs created through the public API are ordinary Jobs: readable through `GET /api/v1/jobs/{id}`, listed by
  `GET /api/v1/jobs` unless the caller sent `public: false`, and marked by `input.source.metadata.public_api`.
- No change to analysis-jobs-api, api-conventions or any result capability: no existing member, status or error
  code changes meaning. `/api/v1/jobs` keeps its behaviour and gets no rate limit.

## Not shared (common rule 13)
Handler structure, the rate limiter implementation and its environment variables and defaults, the public base URL
configuration variable, and test coverage belong to the backend task's local change.

## Based on
backend @ f12021ebe5d250581a9f5cb7e8bf92b2462f2e24, frontend @ d14b9cb5b5183c21d41a12ce5f0cb75e62825631,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ a973ea23909d6cd5d024cea12cc364fa1516fd61.

## Impact
- backend: new handler, composition, summarisation, rate limiter, config.
- frontend: none. `share_url` points at the existing result route `/jobs/{id}` (frontend `src/router.tsx`), which
  this change names as a stable public URL.
- project: none; no new integration suite.
