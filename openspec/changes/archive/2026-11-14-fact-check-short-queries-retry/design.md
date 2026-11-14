# Design: fact_check short queries, plan claims and shorter retry

## Context

`fact_check` searches each qualifying claim's `query` (claim language) and, for
non-English claims, `query_en` (`en`). Google `claims:search` matches keywords of
recorded claim texts; each extra word (date, "beschließt", "allegedly") can reduce
the hits to zero. See proposal.md for the production evidence.

## Decisions

1. **Short queries are a contract of the Claim object, not only of the prompt.**
   The canonical Claim object (topic-extraction-result spec.md:106) already says
   "normally 3-8 words"; it becomes "normally 2-4 words" with the leave-out rules.
   "normally" stays: it describes model output, the orchestrator does not reject or
   cut longer queries (Claim validation, spec.md:127, is unchanged).
2. **Plans and decisions are claims.** "What counts as a claim"
   (topic-extraction-result spec.md:113) replaces "predictions" by "forecasts about
   uncertain outcomes nobody controls" and adds decisions, plans, intentions and
   announcements as claims.
3. **Retry only on a succeeded search with 0 claims.** A failed search keeps the
   existing 429/5xx backoff retry ("Fact check failures", spec.md:120) and gets no
   shorter retry. A search answered from the cache with 0 claims is a succeeded
   search with 0 claims and does get a retry (which may itself be cached).
4. **Retry query, built in code.** Words are split on Unicode whitespace and joined
   by one space. Claim-language search (`query`, also the only search of an English
   claim): the first two entries of `entities` that are non-blank after trimming,
   trimmed and joined by one space. English search (`query_en`): the first three words
   of `query_en`. No retry when the result is empty or equals the original `q` after
   trimming and collapsing whitespace, compared case-insensitively.
5. **At most one retry per search, never retried again.** A retry that also returns
   0 claims ends there. A retry may itself get the existing single 429/5xx backoff
   retry. The duplicate rule of "Search queries per claim" applies only to planned
   searches; a retry is not dropped because another search used the same pair (the
   cache answers it when available). With defaults (3 claims, 2 searches each) a job
   sends at most 6 planned searches and 6 retries (12 searches; plus backoff
   attempts on 429/5xx).
6. **Reporting.** A retry is a Query with `retry_of` = the `q` of the search it
   retries; planned searches have `retry_of: null`. In `queries` it directly follows
   the search it retries, so "planning order" for de-duplication in
   "Fact check list assembly" puts a retry after its original and before the next
   planned search. `for_claim` and `language` equal the original's.
7. **Failures.** A failed retry is listed with `status: failed`, like any failed
   query; the analyzer still succeeds because its original succeeded. A 400/401/403
   on a retry follows "Rejected fact check key" unchanged.

## Compatibility classification

Canonical uses of the changed objects (grep of shared-specs @ 8b9cd65):

| Change | Evidence | Class |
|---|---|---|
| Query gets optional member `retry_of` | fact-check-result/spec.md:70 (Query object), used by spec.md:49,53,74 | shared-additive: new member; clients ignore unknown members (spec.md:49) |
| Extra Query items (retries) in `queries` | spec.md:49 "one per planned search", spec.md:56 Query order | shared-additive: array grows; clients already handle any length (spec.md:145 "SHALL NOT rely on a maximum number of items") |
| `requests_used` counts shorter retries | spec.md:63 | shared-additive: meaning extended to new requests, type unchanged |
| Claim `query` guidance 3-8 → 2-4 words | topic-extraction-result/spec.md:106,109 | non-breaking: string type and validation unchanged; content guidance only |
| Plans/decisions counted as claims | topic-extraction-result/spec.md:113 | non-breaking: same object, more items possible; clients never relied on item count (spec.md:95) |

No shared-breaking change. Affected clients: none today (frontend @ 3e51ec4 has no
reader of these results). Future clients read `retry_of` as optional (absent = null,
from older deployments).

## Risks

- More provider requests (up to 2x) per job; within the default quota, and the cache
  absorbs repeats.
- Shorter queries can match unrelated checks; clients already must compare `claim`
  with `for_claim` (FactCheck object, spec.md:84).
