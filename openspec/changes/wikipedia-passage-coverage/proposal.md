# Proposal: Wikipedia passage coverage label

## Why
junction-2026/project#46. The `wikipedia` analyzer returns a verbatim `passage` per WikiLookup with
`matched_entities` and `matched_numbers`, but says nothing about whether the passage states the claim's number or
date or a different one. The finalizer (`final_synthesis`) therefore has no reliable, verifiable statement to reason
from or quote, and nothing stops it from paraphrasing Wikipedia as if quoting it.

## What Changes
- **wikipedia-lookup-result**: every WikiLookup gets `coverage` (`no_coverage` | `mentioned` | `aligned` |
  `conflicts`) and `evidence_sentence` (verbatim sentence of `passage`, non-null only for `aligned`/`conflicts`),
  decided deterministically in the backend adapter (no LLM), with exact rules for named entities, numbers, dates,
  sentence splitting, a per-WikiLookup scope independent of any cross-language comparison and the downgrade when no verbatim evidence sentence exists. Unknown or absent `coverage` reads
  as `no_coverage`. "No verdict from Wikipedia lookup" is kept and extended to the labels.
- **analysis-jobs-api**: FinalAssessment gets `wikipedia_quotes` (array, `[]` by default). The orchestrator keeps a
  finalizer-proposed quote only when it is a substring of the cited WikiLookup's `passage` and that entry is not
  `no_coverage`; others are dropped without failing finalization.
- **analyzer-service-protocol**: the finalizer response may carry `wikipedia_quotes`; normalization keeps the
  verified ones instead of dropping the member.

All changes are additive (new members; tolerant readers ignore them). No endpoint, status or error code changes.

## Non-goals
No LLM in the Wikipedia analyzer; no true/false verdict from Wikipedia; no change to `news_search` or `fact_check`;
no frontend rendering (the frontend's types already ignore unknown members).

## Based on
backend @ 402553adaf40e950db2f9cd0846d408ab2e79a31, frontend @ 1a14ae98aebb4160df059a3cff5e192186797c90,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 07b1fce6c316aa2ddf926ffab423dd721fb5b9b4.

## Impact
- backend: `internal/adapter/wikipedia.go`, `wikipedia_text.go` (labels), `internal/finalizer/finalizer.go` and
  `internal/job` (FinalAssessment `wikipedia_quotes`), `internal/adapter/llm.go` (`FinalizationSchema`),
  `config/finalizer/prompt.md`, `docs/examples/wikipedia.yaml` (`llm.description`).
- frontend: none required.
- `persistent-job-history` is archived on `main`; jobs it stored before this change lack `coverage` and
  `wikipedia_quotes`; the contract defines both absences.
- Runs in parallel with junction-2026/project#47 (proposed change `wikipedia-cross-language`, shared-specs
  `plan/47-compare-the-two-language-edition` @ 0a6e0c7d4b341dfac79de2c4e4f3aaec5d9a7f07), which also changes
  `wikipedia-lookup-result` and the backend wikipedia adapter. This change does not build on it and touches
  different requirements (see design.md "Overlap with #47"); either can be archived first.
