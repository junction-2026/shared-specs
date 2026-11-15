## Context

Based on backend @ 83ad8c3884aab99fdc94919b89784f8eb004a2fc, frontend @ 162d44f4486433da88f4dcdf089d06d3752287ed, shared-specs @ 24b7969236d03059dd6447481c27afd541fcac7e.

- Finalizer prompt today: "in the language given by <source_language> when present, otherwise in the language of the content" (backend `config/finalizer/prompt.md:52`). The request carries `<source_language>` only when `translation` succeeded with a two-letter code (backend `internal/adapter/llm.go:49-56`).
- Reply retry: `internal/adapter/llm.go:82-138`, reasons `length`, `invalid_json`, `schema`; at most one retry.
- Stopword detector: `internal/adapter/translation_english.go:20-40`, word lists for en, de, fr, es, it, nl, pt.
- `llm_techniques` minimum confidence: `execution.min_confidence`, default 0.5 (backend `internal/registry/llm_techniques_test.go:38`; shared `llm-technique-result/spec.md:108`).
- Claim query: shared `topic-extraction-result/spec.md:106` "normally 2-4 words".

## Sorting by rule 13

| Requirement of #79 | Interface? | Where |
|---|---|---|
| Language of `user_text`, its check and `retry_reason` value | yes: `finalization.result` is read by the frontend and job-text-localization | shared, analysis-jobs-api |
| `evidence_certainty_mismatch` meaning, default min confidence | yes: `llm_techniques` result findings, already in shared llm-technique-result | shared |
| Claim `query` length, one assertion per claim, check-worthiness of group generalisations | yes: Claim object, already in shared topic-extraction-result | shared |
| `propaganda_detection` / `bot_detection` weighting, plain language, posts vs. articles, analyzer descriptions | no: finalizer prompt/config | backend local |
| `<source_language>xx (Name)</source_language>` in the LLM request | no: backend to LLM provider | backend local |

## Change classification (evidence)

| Spec element | Used at | Class |
|---|---|---|
| FinalAssessment `user_text` | analysis-jobs-api/spec.md:143; job-text-localization/spec.md:71 (source_language of user_text) | shared-additive: new guarantee on an existing member; type and meaning unchanged. job-text-localization keeps `source_language` null when translation did not run (the text is then English, but saying "null = unknown" stays true); not changed here. |
| `retry_reason` values | analysis-jobs-api/spec.md:461; topic-extraction-result/spec.md:20,159 reuse the analysis-jobs-api rules | shared-additive: new value in an "includes" list; clients already treat unknown values generically (spec.md:461). Only the finalizer emits it; topic_extraction does not. |
| Language mismatch after a retry does not fail | analysis-jobs-api/spec.md:478 "LLM reply retry failure" | shared-additive: a language mismatch is not an invalid reply, so that requirement does not apply; no case that failed before now succeeds or vice versa except that a German-for-English first reply now triggers a retry. |
| `evidence_certainty_mismatch` definition | llm-technique-result/spec.md:20; glossary `definition` (llm-technique-result/spec.md:55) | shared-breaking in meaning only (narrower), member unchanged. Clients: frontend renders findings by label; no code change. The fixed glossary `definition` text stays as is (#79 scopes changes to prompts); its wording "more certainty than the evidence supports" is still correct for the narrowed label. |
| Default minimum confidence 0.5 -> 0.6 | llm-technique-result/spec.md:108 | shared-breaking in a default value only: fewer findings. Clients ignore count; no migration. Stored results are not recomputed. |
| Claim `query` 2-4 -> 3-8 words | topic-extraction-result/spec.md:106; consumed by fact-check-result (query from claims) | shared-additive in practice: "normally" guidance, no validation change; fact_check sends whatever `query_en` holds. |
| One assertion per claim | topic-extraction-result/spec.md:112-113, :134 (cap 5 kept) | shared-additive: more, narrower claims; cap and ordering unchanged. |

## Decisions

1. **Language check is soft.** A mismatch triggers the existing single reply retry but never fails finalization: when the retry is still in the wrong language, or the retry's reply is invalid, or the retry request fails, the orchestrator keeps a valid reply (the retry's when valid, otherwise the first) with `attempts: 2` and the language `retry_reason`. Rejected: treating it as invalid output (would fail jobs on a heuristic).
2. **Only confident detections count.** The check runs only when the expected language is one the deployment's detector knows (at least en, de, fr, es, it, nl, pt) and the detector confidently names another known language. Short or mixed texts never trigger it.
3. **`retry_reason` names the language** (`user_text must be written in German`), as #79 asks; it uses the English language name so it is stable across locales. Clients already show unknown values generically.
4. **No retry beyond one.** A first reply that was retried for `schema`, `length` or `invalid_json` is not retried again for language; its `retry_reason` stays the first reason.

## Overlap with active changes

- `ai-country-association` (#75) adds `Job.country_association` in analysis-jobs-api; this change touches FinalAssessment and retry requirements only. No shared requirement overlap; `base_changes: []`.

## Risks

- Stopword heuristic false positives on English text quoting German: mitigated by "confidently" (same thresholds as the translation English check) and the soft failure mode.
