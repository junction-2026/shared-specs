# Job text localization (junction-2026/project#45)

## Why
With the UI in Arabic (or any language other than the analysed content's), result explanations stay in the content's
language: the finalizer writes `user_text` "in the language of the content" (backend `config/finalizer/prompt.md:36`),
LLM technique `explanation`s are written in `explanation_language`, and the plain-language glossary follows the
content's `source_language` and has no Arabic at all (technique-classifier-result "Plain-language result members";
backend `internal/adapter/technique_glossary.go:19` ships en, fi, sv, de, fr, es, ru, uk). A French article viewed in
Arabic therefore shows French technique names, definitions and explanations. No API lets a client get the
model-written texts of a finished job in another language without re-running the analysis.

## What changes
- New capability `job-text-localization` (shared, additive): `GET /api/v1/jobs/{id}/localization?language=<code>`
  returns the job's model-written presentation texts (finalizer `user_text`, LLM technique finding `explanation`s)
  in the requested UI language, each marked `original`, `translated` or `unavailable`. It never re-runs analyzers or
  the finalizer, never changes the Job and emits no events. Original evidence (input content, spans, quotes, claims,
  headlines, fact-check reviews) is never translated by it.
- technique-classifier-result: MODIFIED "Plain-language presentation" and ADDED "Client localization of glossary texts": a client whose UI language differs from
  `explanation_language` MAY show its own localization of the glossary name, definition and `why` template keyed by
  the stable technique `name` (or LLM `label`), keeping span `text` verbatim. Wording "SHALL show plain_language" is
  relaxed only for that case; results without `plain_language` keep the existing fallback.
- Not shared (common rule 13): frontend catalogs, technique-name catalog, RTL layout, language switching, history and
  explore localization (frontend local changes); translation provider, prompt, cache and fixed-text table (backend
  local change).

## Impact
- Shared capabilities: `job-text-localization` (new), `technique-classifier-result` (one requirement modified,
  additive for clients: allows more, forbids nothing that was allowed).
- backend: new route, translation of presentation texts via the deployment's LLM translation provider, per
  (job, language) cache, fixed translations of the orchestrator's insufficient-evidence text. No change to detection,
  thresholds, finalizer rules, confidence, evidence extraction, fact-checking or retrieval.
- frontend: static i18n audit and RTL for all views; result localization (technique catalog by `name`, request of
  the new endpoint on language switch, labelled machine translation, original quotes kept LTR/verbatim).
- project: no new integration suite (`full-e2e` is still a placeholder); repo-ci of each repository gates the work.
- Active shared change `persistent-job-history` (junction-2026/project#43) touches `analysis-jobs-api` and
  `analysis-job-events` only; this change touches neither. Its backend SQLite job store is already merged
  (backend @ 402553ad); the new route reads jobs through that store, so persisted and recovered done jobs are
  localized like any other done job.
- Parallel feature junction-2026/project#47 (`wikipedia-cross-language`, plan @ 0a6e0c7d) modifies
  `wikipedia-lookup-result` only; this change does not touch it. Its new `cross_language` value is an enum (class A,
  localized by the frontend catalog) and Wikipedia passages and compared values are original source material
  (class C, never translated by this endpoint). Not a base change: nothing here depends on it.

Based on backend @ 402553adaf40e950db2f9cd0846d408ab2e79a31, frontend @ 1a14ae98aebb4160df059a3cff5e192186797c90,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ b4a04a191450549e9d263166bd8cc2904044cff6
(re-planned around junction-2026/project#47 and #43).
