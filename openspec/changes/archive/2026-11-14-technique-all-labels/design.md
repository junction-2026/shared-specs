# Design: technique-all-labels

## Contract surface and classification

Canonical references are shared-specs @ cc519dd (`openspec/specs/technique-classifier-result/spec.md`,
which already contains the archived #17 span requirements). `grep -rn "techniques\b\|Detection\|offsets_in"
openspec/specs` finds these objects only in `technique-classifier-result`; other capabilities carry the
result verbatim (`analysis-jobs-api/spec.md:74` AnalyzerRun `result`, `analysis-job-events/spec.md:34`
`analyzer.succeeded`).

| Element | Canonical | Change | Classification |
|---|---|---|---|
| Analyzer `techniques`, `depends_on: translation`, skip on failed translation | `:8-17` | none | unchanged |
| Technique names | `:19-24` | same 18 names; now also the known TechniqueScore `label` values | shared-additive |
| TechniqueClassification `results` (ModelResult, TechniqueScore) | `:26-31` ("at least", "Clients SHALL ignore unknown members") | new members | shared-additive |
| TechniqueClassification `model`, `threshold`, `thresholds`, `techniques`, `max_score`, `latency_ms` | `:26-45` | removed (moved into `results[]`) | **shared-breaking** (removed members) |
| Routing | `:33-38` | one model by `short` limit → one or both NCI models by two word bounds | **shared-breaking** (changed meaning) |
| `detected` membership | `:47-56` | was document score ≥ per-technique threshold of the single model; now `above_cutoff` in at least one ModelResult; ordered by the names list instead of by score | **shared-breaking** (changed meaning and order) |
| Detection `score` | `:48` | removed (no merged score); Detection gains `models` | **shared-breaking** (removed member) + additive |
| Detection `name`, `display`, `explanation`, `spans` | `:48`, `:115-120` | unchanged | unchanged |
| `sentences`, SentenceDetection, `offsets_in`, `sentences_truncated` | `:58-74` | removed | **shared-breaking** (removed) |
| Unknown label | `:76-85` | was `invalid_output`, now kept with `known: false` | **shared-breaking** (changed status for an existing case: run now succeeds) |
| `error.code` values | `:76`, `analysis-jobs-api` | same codes; new condition: either of two required models fails | shared-additive |
| Credential rule | `:87-92` | none | unchanged |
| Presentation | `:94-99` | rewritten for `label`/`display`/`above_cutoff`; sentence text gone | wording follows members; no new obligation on the existing client |
| Span result members, Span status, TechniqueSpan, Span offsets, ordering, Span method, Sentence spans only for detected, Phrase spans, Phrase candidate rejection | `:101-113`, `:129-155`, `:164-187` | none | unchanged |
| Detected techniques keep empty spans | `:115-120` | drops the sentence about `sentences[].techniques` | follows removal |
| Span highlighting presentation | `:122-127` | "no translation as the user's words" no longer names `offsets_in` | follows removal |
| Sentence spans for English input | `:157-162` | "independent of `model`" → "independent of which models produced `results`" | follows removal |
| Span failures keep the classification | `:189-199` | invariants now `results` and `detected` membership instead of `techniques`, `sentences`, `offsets_in` | follows removal |

Delta mechanics: "Detected techniques" and "Technique result presentation" are REMOVED and
re-ADDED as "Detected techniques by cutoff" + "Detection object" and "Technique score presentation" +
"Technique score interpretation", because their old scenarios (per-technique override, markup in a
sentence) describe removed behaviour and a MODIFIED block may not drop scenarios. All other #17 span
requirements are kept verbatim or MODIFIED only where they named removed members.

### Affected clients and migration

- **frontend** @ 1abe19a (`src/job/JobView.tsx:10-17`, `src/job/api.ts:1`): reads only
  `detected[].name`, `display`, `explanation`, `spans` and `span_status`, all kept with the same
  types. It never reads `sentences`/`offsets_in` (`job-result-view` spec forbids rendering them),
  `techniques`, `thresholds` or Detection `score`. **No migration needed**; the frontend may show
  `results` later in its own feature.
- **backend LLM finalizer**: receives the result verbatim with the analyzer's `llm.description`
  (backend-local config); the backend task rewrites the description in the same change.
- **Stored results**: jobs finished before the backend deploy keep the #15/#17 shape. They still
  have `detected` with spans, so the frontend shows them as before; a client reading `results`
  treats its absence as "no per-model scores". No data migration.
- **Deployments**: registry keys change (backend-local); the backend rejects the old keys at startup
  with a message naming the replacement, so no deployment silently changes cutoffs.

### Tolerant-reader style

Every object is "at least"; `model`, `span_method`, `span_status` and `error.code` values "include".
The only "exactly" is one TechniqueScore per known label per ModelResult: a client indexing by
`label` must not see two scores for one label from one model.

## Routing

`words` = number of whitespace-separated words of `translated_text`.

| words | models run (defaults) |
|---|---|
| `< technique_min_words` (40) | `nci-social` |
| `technique_min_words .. social_max_words` (40–80) | `nci-technique`, `nci-social` |
| `> social_max_words` (80) | `nci-technique` |

The backend requires `technique_min_words <= social_max_words + 1` so every text gets at least one
model. Routing ignores `input.source`. 80 words is a conservative bound for 128 BERTweet tokens
(~1.5 tokens per word + 2 special tokens); the backend has no tokenizer.

## Labels

Known labels: the 18 names of the canonical spec. Per ModelResult each known label appears once in
the names order, then extra labels in the model's order with `known: false` and `display` equal to
the label. A missing known label, a duplicate, a non-string or empty label, or a score outside
[0, 1] is `invalid_output`.

## detected

`detected` = known names with `above_cutoff: true` in at least one ModelResult, in names order;
`models` lists those ModelResults' `model` in `results` order. It is a membership list, not a
combined score. The span step (#17) runs unchanged on this list: English → sentence model
(`spans.sentence_model`, its own threshold config) on `Job.input.content`; other languages → LLM
phrases validated as exact substrings. The span step's sentence model is not one of the
classification requests of "English translation only".

## Purpose line

The canonical Purpose mentions "the sentences that carry them". A delta cannot change Purpose; the
archive step of this change SHALL rewrite it to: "Result object of the propaganda technique
analyzer: every technique label with its score from the NCI document model, the NCI short-post
model or both on the English translation of a job's text, each model's cutoff, the detected
techniques and their spans in the user's original text, as clients read it from the analysis job
API and event stream."

## Backend-local (not in this change)

ML service request/response protocol, endpoints and headers, `social_max_words`,
`technique_min_words`, per-model `cutoff` keys, concurrency of the two calls, timeout, registry
validation and old-key rejection, `llm.description` text, example and README, tests.

## Risks

- The word bound may send an 80+-word text of very short words only to `nci-technique` although it
  would fit 128 tokens. Acceptable: the social model never gets truncated input; bounds are config.
- Scores of the two models are not comparable; the spec forbids merging or comparing them.
- `detected` now flags a technique above the lower `nci-social` cutoff (0.3) for 40–80-word texts
  where #15 used one model; the `models` member makes the source visible.
