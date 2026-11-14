# Design: technique-all-labels

## Contract surface and classification

Canonical references are shared-specs @ c999ac2. `grep -rn "technique\|Detection\|offsets_in" openspec/specs`
finds these objects only in `technique-classifier-result`; no other capability reuses them.

| Element | Used at | Change | Classification |
|---|---|---|---|
| AnalyzerRun `techniques`: id, category, `depends_on: translation`, skip on failed translation | `technique-classifier-result/spec.md:8-17` | wording only ("no model request") | unchanged |
| TechniqueClassification members | `technique-classifier-result/spec.md:26-31`; delivered verbatim via `analysis-jobs-api/spec.md:74` and `analysis-job-events` `analyzer.succeeded` | `results` and `words` kept/added; `model`, `threshold`, `thresholds`, `techniques`, `detected`, `max_score`, `sentences`, `offsets_in`, `sentences_truncated`, `latency_ms` removed from the top level | **shared-breaking** (removed members) |
| `model` values | `technique-classifier-result/spec.md:33-38` | `short`/`long` → `nci-technique`/`nci-social`, now inside ModelResult | **shared-breaking** (changed values) |
| Routing | `technique-classifier-result/spec.md:33-38` | one model by `short` limit → one or both by two word bounds | **shared-breaking** (changed meaning) |
| TechniqueScore | `technique-classifier-result/spec.md:40-45` | `name` → `label`; adds `model`, `cutoff`, `above_cutoff`, `known`; keeps `display`, `score` | **shared-breaking** (renamed member) |
| Detection, SentenceDetection, offsets | `technique-classifier-result/spec.md:47-74` | removed | **shared-breaking** (removed) |
| Unknown label | `technique-classifier-result/spec.md:76-85` | was `invalid_output`, now kept with `known: false` | **shared-breaking** (changed status for an existing case: run now succeeds) |
| `error.code` values `invalid_output`, `adapter_error`, `timeout`, `cancelled` | `technique-classifier-result/spec.md:76`, `analysis-jobs-api/spec.md:81` | same codes; new condition: either of two required models fails | shared-additive |
| Credential rule | `technique-classifier-result/spec.md:87-92` | unchanged | unchanged |
| Presentation | `technique-classifier-result/spec.md:94-99` | REMOVED and replaced by ADDED "Technique score presentation" (`label`, `display`, `above_cutoff`; no sentence text) | shared-breaking (wording follows the new members) |

### Affected clients and migration

- **frontend** @ 3e51ec4: no job/analyzer client; nothing to migrate. A future client reads
  `results[]`.
- **backend LLM finalizer**: receives the result verbatim with the analyzer's `llm.description`
  (backend-local config); the backend task updates the description in the same change.
- **Stored results**: jobs finished before the backend deploy keep the #15 shape. Clients SHALL treat
  a `techniques` result without a `results` array as "no technique analysis available" (Technique
  result presentation requirement). No data migration.
- **Deployments**: registry keys change (backend-local); the backend rejects the old keys at startup
  with a message naming the replacement, so no deployment silently changes cutoffs.
- **#17 technique-spans plan** (b89838e, unmerged): builds on removed members; must be re-planned.

### Tolerant-reader style

Every object is described as "at least"; `model` values and `error.code` lists "include". The only
"exactly" left is the 18 known labels per ModelResult (one TechniqueScore per known label, no
duplicates): a client indexing by `label` must not see two scores for one label from one model.

## Routing

`words` = number of whitespace-separated words of `translated_text`.

| words | models run (defaults) |
|---|---|
| `< technique_min_words` (40) | `nci-social` |
| `technique_min_words .. social_max_words` (40–80) | `nci-technique`, `nci-social` |
| `> social_max_words` (80) | `nci-technique` |

The backend requires `technique_min_words <= social_max_words + 1` so every text gets at least one
model. Routing ignores `input.source`.

## Labels

Known labels: the 18 SemEval-2020 Task 11 names of the canonical spec. Per ModelResult each known
label appears once, then extra labels in the model's order with `known: false` and `display` equal
to the label. A missing known label, a duplicate, a non-string or empty label, or a score outside
[0, 1] is `invalid_output`.

## Purpose line

The canonical Purpose still mentions "detected techniques and the sentences that carry them". A
delta cannot change Purpose; the archive step of this change SHALL rewrite it to: "Result object of
the propaganda technique analyzer: every technique label with its score from the NCI document model,
the NCI short-post model or both, on the English translation of a job's text, with each model's
cutoff, as clients read it from the analysis job API and event stream."

## Backend-local (not in this change)

ML service request/response protocol, endpoints and headers, `social_max_words`,
`technique_min_words`, per-model `cutoff` keys, concurrency of the two calls, timeout, registry
validation and old-key rejection, removal of the `job_content` input, the `llm.description` text,
example and README, tests.

## Risks

- The word bound may send an 80+-word text of very short words only to `nci-technique` although it
  would fit 128 tokens. Acceptable: the social model never gets truncated input; bounds are config.
- Scores of the two models are not comparable; the spec forbids merging or comparing them.
