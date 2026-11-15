# Design: public-analysis-api

## Context
Based on backend @ f12021ebe5d250581a9f5cb7e8bf92b2462f2e24 (`internal/httpapi/httpapi.go` routes,
`internal/httpapi/jobs.go` create/get, `internal/chat/limiter.go` token bucket, `engine.CreateRequest`), frontend @
d14b9cb5b5183c21d41a12ce5f0cb75e62825631 (`src/router.tsx` serves `/jobs/<id>`) and shared-specs @ a973ea2.

## Decisions

### Thin wrapper, one job per request
The handler builds an `engine.CreateRequest` (all analyzers, `Finalize: true`) and calls the existing engine. Several
texts become one `input.content`; scraping uses the existing `scrape` path with ScrapeRequest defaults. No new job
store, no second orchestrator. GET reads the same store and maps the Job to a PublicAnalysis.

### Separate path `/api/v1/public/analyses`
A separate resource keeps the Job object and `/api/v1/jobs` unchanged, lets the public endpoints carry their own
rate limit, and gives integrators a small stable object instead of the full Job. The PublicAnalysis `id` is the job
id, so the same id works on `/api/v1/jobs/{id}` and the web page.

### Result shape: `result` object, not flattened
`verdict`, `confidence`, `user_text` and `produced_by` live under `result`, null until finalization completed. This
separates "not finished" / "finalization failed" (`result: null`, see `finalization_status`) from the values and
mirrors `finalization.result` of the Job, so the meaning of the verdict fields is unchanged (non-goal of #100).

### Composition format
Post only: `input.content` is the post exactly as sent, so a public post analyses identically to the same text
pasted in the UI. Otherwise blocks `Post:\n<trimmed post>` and `Comment <n>:\n<trimmed comment>` (n counts kept
comments from 1) joined by a blank line. Blank comments are dropped. The separators are plain text; a comment that
itself contains `Comment 2:` can imitate a block boundary. That is accepted: the analyzers do not rely on the
structure, and `public_api` metadata records the real counts.

### Status codes
The parent issue requires 400 for an empty body or missing content. Empty and malformed bodies are already 400
`invalid_request` under api-conventions "Common error codes". "No content at all" gets its own code
`missing_content` (400), allowed by "Endpoints MAY define further codes"; it is a new condition on a new endpoint.
Wrong member types stay 422 `validation_failed` as api-conventions requires. The capability states the precedence
explicitly so clients and tests agree.

### Rate limit
One global token bucket per endpoint (create, read), checked before the body is read, so every request counts,
including ones rejected later. Separate buckets keep polling from starving submissions. 429 uses the same envelope
as analysis-chat-api "Chat request limits" (`rate_limited`, `Retry-After`, `details.retry_after_s`). Values are
deployment configuration (backend local change). `/api/v1/jobs` stays unlimited: the UI uses it, and adding a limit
there would change an existing case (breaking). This means the limit protects the documented public entry point,
not the box against a client that deliberately uses `/api/v1/jobs`.

### share_url
The backend does not know the web client's origin, and deriving it from `Host` would allow header injection into
the returned link. The deployment configures a public base URL; `share_url` is `<base>/jobs/<url-escaped id>` or
null when unconfigured. The frontend already serves `/jobs/<id>`; this change makes that path a stable contract.

### No CORS
The intended callers are platform and outlet servers. Browser calls from other origins are not added here (no
existing CORS convention in shared specs); a later change can add it additively.

## Compatibility classification (rule: every place an endpoint/object is used)
- `POST /api/v1/public/analyses`, `GET /api/v1/public/analyses/{id}`: new endpoints — **shared-additive**.
- PublicAnalysis and its sub-objects: new objects — **shared-additive**. They are derived from, and reference, the
  existing objects without changing them: Coverage (analysis-jobs-api spec.md:110), FinalAssessment
  (analysis-jobs-api spec.md:142), Verdict values (spec.md:214), Confidence semantics (spec.md:221), User text
  rendering (spec.md:228), Scrape failure causes (spec.md:314), Detection / TechniqueScore / TechniqueSpan
  (technique-classifier-result spec.md:198, 256, 106), LlmTechniqueFinding / LlmTechniqueSpan (llm-technique-result
  spec.md:47, 61), TextBotDetection (bot-detection-result spec.md:26, 44), FactCheck (fact-check-result spec.md:87),
  Article (news-search-result spec.md:65), ClaimLookup / WikiLookup / coverage (wikipedia-lookup-result spec.md:114,
  121, 210).
- Job object (analysis-jobs-api spec.md:56): unchanged members. Public-API jobs set
  `input.source.metadata.public_api`; `source.metadata` is a free-form object kept verbatim (Input object,
  spec.md:8), so a new key in it is **shared-additive**. Job visibility (spec.md:613) applies unchanged.
- Error codes `missing_content` (new code, new condition) and `rate_limited` on the new endpoints — **shared-additive**.
  `rate_limited` already exists in analysis-chat-api (spec.md:124) with the same shape.
- api-conventions (spec.md "Common error codes", "Error envelope", "Tolerant reader"): followed, not modified.
- `/api/v1/jobs` and all its cases: unchanged.
- No **shared-breaking** change; no client migration needed. The frontend is not a client of the new endpoints.

## Risks
- The global limit can be exhausted by one caller, denying others (accepted for a demo box; per-key quotas are a
  non-goal).
- Jobs created with `public` omitted appear in the public history listing like UI jobs; integrators that do not want
  this send `public: false`.
