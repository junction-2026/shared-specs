# Proposal: Make fact_check find fact-checks

## Why

Parent feature junction-2026/project#13. In production (2026-11-14) `fact_check` returns
no fact-checks even for widely checked claims. Google Fact Check Tools `claims:search`
behaves like a keyword match on the recorded claim text: the extractor's queries
("EU beschließt Bargeld abschaffen 2027", "EU decides to abolish cash 2027") return 0,
while "EU Bargeld abschaffen" returns 5 reviews (AFP, dpa, BR). In addition the
extractor drops statements about what someone plans or wants to do ("Die EU will das
Bargeld abschaffen") as "predictions", although these are among the most fact-checked
claim types.

Based on: backend @ 669d0a92ff66fcb10066bff73f341e5d9e747fde (Go orchestrator;
`config/extractor/prompt.md`, `internal/adapter/factcheck.go`), frontend @
3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (no client of `topic_extraction` or
`fact_check` results), project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e`
is a placeholder), shared-specs @ 8b9cd651a421ab9b4b99aa2183a47cf453704101 (no active
shared change).

## What Changes

- **topic-extraction-result** (modified): Claim `query` / `query_en` become 2-4 word
  keyword phrases (actor plus key object or action noun; no dates, relative time,
  verbs of deciding or saying, hedges or framing). Statements that someone has
  decided, plans, wants or will do something count as claims; only forecasts about
  outcomes nobody controls stay excluded. The Claim object members and types are
  unchanged.
- **fact-check-result** (modified): a search that succeeds with 0 claims gets exactly
  one shorter retry built in code (first 2 `entities` for the claim-language search,
  first 3 words of `query_en` for the English search). The retry is a Query with the
  new optional member `retry_of` (the `q` it retries; null for planned searches), is
  listed right after the search it retries, counts in `requests_used`, is cached like
  any search, and its matches enter `fact_checks` with `query` = the retry `q`.

Not changed: the claims JSON schema and existing members, no LLM call in the retry,
no frontend work, no other provider.

## Impact

- backend: extractor prompt, `fact_check` adapter, tests (one child task).
- frontend: none (no client of these results yet); future clients read `retry_of`
  as optional.
- project: none; no integration suite covers this (`full-e2e` is a placeholder).
