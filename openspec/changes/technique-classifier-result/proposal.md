# Proposal: Propaganda technique classifier result (`techniques`)

## Why

Parent feature junction-2026/project#15. The backend gets a `technique_classifier`
adapter that scores the English translation of a job's text for the 18 SemEval-2020
Task 11 propaganda techniques, with a short-text model (BERTweet, threshold 0.3) or a
long-text model (ModernBERT, threshold 0.5) chosen by word count, and also scores each
sentence so clients can highlight the wording that carries a technique. The result
reaches clients verbatim through `Job.analyzers[].result` and `analyzer.succeeded`
(`analysis-jobs-api/spec.md:74`), and the frontend highlight view is the expected
follow-up, so the result shape (model, scores, detections, sentence offsets and what
they index) is an interface between repositories. That interface is this change.

Based on: backend @ c9d39e4ae1902f33669bdb0f5112361b35625308 (`propaganda_detection`
adapter `internal/adapter/propaganda.go`, `mistral_translation` returning
`source_language` and `translated_text` from `normalized_content`,
`internal/adapter/translation.go:19-24,142`; bindings `internal/adapter/adapter.go:74-101`),
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (health page only, no job client),
project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e` only),
shared-specs @ 8324422d6348be58949a9f3149d7d6a772f7e94f (no active change on main;
unmerged plan branch `plan/14-merge-the-scraper-into-the-main` modifies
`analysis-jobs-api` and `social-scraper-api` only, disjoint from this change).

## What Changes

- **technique-classifier-result** (new capability): analyzer id `techniques`; the
  TechniqueClassification result object (`model`, `words`, `threshold`, `thresholds`,
  `techniques`, `detected`, `max_score`, `sentences`, `offsets_in`,
  `sentences_truncated`, `latency_ms`); the 18 technique names; TechniqueScore,
  Detection and SentenceDetection objects; offset unit (UTF-16 code units) and the
  string the offsets index; failure codes; credential-free errors; plain-text
  rendering and "indicator, not proof" presentation rules for clients.

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
`api-conventions`. No new skip reason or error code: the analyzer uses the canonical
`dependency_failed`, `adapter_error`, `timeout`, `invalid_output`, `cancelled`
(`analysis-jobs-api/spec.md:81,88`).

## Decisions for approval

- **Result shape is shared; everything that produces it is backend-local**: the ML
  service request/response, model routing threshold (`short_max_words`), sentence
  splitter, `max_sentences`, per-model endpoints/thresholds, registry config, display
  name texts and the LLM description. The ML service is a third-party deployment, not
  a registered repository, so its contract is a backend local requirement.
- **Offsets are UTF-16 code units** so a browser can `slice` them directly; a Go
  implementation converts. Every reported sentence carries its `text`, so a client can
  verify the slice.
- **`offsets_in: "original"` only when every reported sentence is found verbatim** in
  `Job.input.content`. The adapter always classifies `translated_text` (for English,
  the translator returns the text unchanged, but an LLM may still alter whitespace or
  characters, and `normalized_content` differs from `content` for HTML and CRLF).
  When `source_language` is `en` and every reported sentence is located, in order, in
  `Job.input.content`, offsets index the original; otherwise they index the
  translation's `translated_text` and `offsets_in` is `"translation"`. This keeps
  `content.slice(start, end) === text` true in every case.
- **Fixed analyzer id `techniques`** (as in the issue's registry entry), category
  `propaganda`; clients treat a missing, skipped or failed run as "no technique
  analysis", never as "no techniques".
- **`thresholds` member added** (effective threshold for each of the 18 techniques
  after per-technique overrides), so clients and the LLM can tell why a score is or is
  not detected. Additive to the issue's shape.
- **No frontend task** (issue non-goal). **No project task**: no integration suite
  exercises analyzers against ML services; backend tests use stub services.
- **One backend task** (adapter, registry validation, display map, example, README,
  tests: about 8 files in one area).

## Impact

- backend: new `technique_classifier` adapter and registry keys, display-name map,
  `docs/examples/technique_classifier.yaml`, README section, stub-service tests.
- frontend, project: no change.
