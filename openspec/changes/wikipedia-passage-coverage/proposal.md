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
  sentence splitting and the downgrade when no verbatim evidence sentence exists. Unknown or absent `coverage` reads
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
backend @ 2ee817ed318928e5ecb2d6ce9aab822a7cc99f16, frontend @ 530723a5ee7c097b107eb9b9eb4258ec027f5663,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ b4a04a191450549e9d263166bd8cc2904044cff6.

## Impact
- backend: `internal/adapter/wikipedia.go`, `wikipedia_text.go` (labels), `internal/finalizer/finalizer.go` and
  `internal/job` (FinalAssessment `wikipedia_quotes`), `internal/adapter/llm.go` (`FinalizationSchema`),
  `config/finalizer/prompt.md`, `docs/examples/wikipedia.yaml` (`llm.description`).
- frontend: none required.
- Active change `persistent-job-history` touches other requirements of analysis-jobs-api; no overlap. Jobs stored
  before this change lack `coverage` and `wikipedia_quotes`; the contract defines both absences.
