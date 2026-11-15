## Why

junction-2026/project#79: a review of 140 completed analyses (backend v0.1.59) found prompt-level problems. Three of them change behaviour that clients see through the API and that the canonical specs already describe:

- 15 of 114 English inputs got a German or Dutch `user_text`. The canonical specs say nothing about the language of `user_text`, so the frontend and the job-text-localization endpoint cannot rely on one.
- `evidence_certainty_mismatch` fires on ordinary news reporting (152 of 213 `llm_techniques` findings). The canonical label definition (llm-technique-result "LLM technique labels") is too broad, and the default minimum confidence is 0.5.
- Fact-check queries of `topic_extraction` claims are too generic, and bundled accusations get low check-worthiness. The canonical Claim object asks for a "normally 2-4 words" `query`.

The other fixes of #79 (finalizer weighting of `propaganda_detection`, the `bot_detection` rule, plain-language wording, posts versus articles, the `propaganda_detection` description, how the finalizer request is built) are backend prompts and runtime and are planned in the backend's local change.

## What Changes

- `analysis-jobs-api`:
  - ADDED "FinalAssessment user_text language": an `llm` finalizer writes `user_text` in the language of the `translation` result's `source_language`, English when it is unknown.
  - ADDED "Finalizer output language check": after a valid reply, the orchestrator checks the language of `user_text` and sends the one reply retry when it is confidently another language; a still-wrong retry keeps a valid reply instead of failing.
  - MODIFIED "LLM reply retry members": new `retry_reason` value `user_text must be written in <English language name>`. Additive (the list "includes" values and clients already treat unknown values as "retried for another reason").
- `llm-technique-result`:
  - MODIFIED "LLM technique labels": narrower `evidence_certainty_mismatch` definition; attributed reporting is not a mismatch.
  - MODIFIED "LLM finding filtering": default minimum confidence 0.6 (was 0.5).
- `topic-extraction-result`:
  - MODIFIED "Claim object": `query` / `query_en` are 3-8 words naming actor, assertion and key number or place.
  - MODIFIED "What counts as a claim": one checkable assertion per claim; group generalisations are check-worthy (>= 0.6).

No member is added, removed or renamed; no endpoint changes.

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `analysis-jobs-api`: `user_text` language and its check; new `retry_reason` value.
- `llm-technique-result`: `evidence_certainty_mismatch` definition and minimum confidence.
- `topic-extraction-result`: claim query and claim splitting rules.

## Impact

- backend: finalizer prompt, request (`<source_language>` always sent with its English name), language check and retry; `llm_techniques` prompt and default `min_confidence`; extractor prompt. Plus the local-only prompt fixes of #79.
- frontend: no change required. It already renders `user_text` as plain text and treats unknown `retry_reason` values generically; fewer `llm_techniques` findings and more, narrower claims need no code change.
- project: no new integration suite.

Based on backend @ 83ad8c3884aab99fdc94919b89784f8eb004a2fc, frontend @ 162d44f4486433da88f4dcdf089d06d3752287ed, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 24b7969236d03059dd6447481c27afd541fcac7e.
