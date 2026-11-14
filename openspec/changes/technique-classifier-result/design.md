# Design: technique-classifier-result (revision for junction-2026/project#16)

## Contract surface and classification

| Element | Where clients see it | Classification | Evidence |
|---|---|---|---|
| AnalyzerRun `techniques` with TechniqueAnalysis `result` | `Job.analyzers[]`, `analyzer.succeeded` `data.analyzer.result` | shared-additive vs canonical specs (new analyzer id; result is a service-defined object stored verbatim) | `analysis-jobs-api/spec.md:74`, `analyzer-service-protocol/spec.md:65` |
| Failure codes `adapter_error`, `timeout`, `invalid_output`, `cancelled` | AnalyzerRun `error.code` | existing codes, existing meaning | `analysis-jobs-api/spec.md:81` |
| Skip `dependency_failed` / `dependency_skipped` when `translation` did not succeed | AnalyzerRun `reason` | unchanged canonical behaviour | `analysis-jobs-api/spec.md:88` |
| TechniqueClassification of #15's draft → TechniqueAnalysis | same | **breaking against #15's unarchived draft only** (members removed/renamed, `model` values changed, unknown labels now kept) | `changes/technique-classifier-result/specs/...` @ 2dd0006 |

Affected clients of the breaking part: none in code. frontend @ 3e51ec4 has no job or
analyzer client; backend @ 69f5c6d has no `techniques` producer. The only consumer is
#15's planned backend child, which is superseded by this plan's backend child
(migration: implement this revision instead). `grep -rn "technique" openspec/specs` on
shared-specs @ 2dd0006 finds nothing in canonical specs, so no canonical requirement
changes. No "exactly" clause is used; every object is "at least".

## Routing

`words` = number of whitespace-separated words of `translated_text`.

| words | models run |
|---|---|
| `< technique_min_words` (40) | `nci-social` |
| `technique_min_words..social_max_words` (40–80) | `nci-technique`, `nci-social` |
| `> social_max_words` (80) | `nci-technique` |

Requires `technique_min_words <= social_max_words` (registry validation), so every
text gets at least one model. 80 words is a conservative bound for BERTweet's 128-token
input (≈1.5 tokens per English word plus `<s>`/`</s>`). Routing ignores `input.source`.

## Labels

The 18 known labels are the SemEval-2020 Task 11 names already listed in #15's draft.
Per ModelResult: each known label appears once; extra labels returned by the model are
appended with `known: false`; a missing known label, a duplicate label, a non-string
label or a score outside [0, 1] makes the run `invalid_output`.

## Backend-local (not in this change)

ML service request/response protocol and validation, model endpoints and headers,
`social_max_words`, `technique_min_words`, per-model `cutoff` config, concurrency of the
two calls, timeout, registry validation (text must be bound to `$analyzers.<translation id>`),
the `llm.description` text, docs example and README.

## Risks

- The word bound may route a text that would fit 128 tokens to `nci-technique` only
  (for 80+ short words). Acceptable: it never overflows the social model; bounds are config.
- Scores of the two models are not comparable; the spec forbids merging them.
