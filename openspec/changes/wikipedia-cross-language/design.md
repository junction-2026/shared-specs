# Design: Wikipedia cross-language agreement

## Base
- W2 is archived (`openspec/changes/archive/2026-11-14-wikipedia-claim-lookup`) and canonical in
  `openspec/specs/wikipedia-lookup-result/spec.md`; backend implements it in `internal/adapter/wikipedia.go`
  (`claimLookup` struct, lines 43-48). The only active shared change, `persistent-job-history`, touches
  `analysis-jobs-api` / `analysis-job-events` only: no overlap.
- Frontend @ 530723a has no code reading the `wikipedia` AnalyzerRun (grep for `wikipedia` in `frontend/src`: none),
  project @ 441ecbf has no E2E for it. So no existing client reads ClaimLookup.

## Shape
`cross_language` is a string (as the parent issue states: "set to one of agree / discrepancy / gap") so clients can
switch on it directly; the quoted values live in a sibling member `cross_language_differences`, one entry per wiki
in `languages` order, each with `language`, `url` and the values found only in that wiki's passage. Pairing a
specific number of one passage with "the" number of the other is not decidable deterministically without
alignment, so each side lists its own unmatched values; that quotes both sides with language and url as required.

Example (discrepancy):
```json
{"claim": "...", "check_worthiness": 0.8, "search_mode": "fulltext", "wikis": [<de found>, <en found>],
 "cross_language": "discrepancy",
 "cross_language_differences": [
   {"language": "de", "url": "https://de.wikipedia.org/w/index.php?title=Rente&oldid=1", "values": [{"kind": "number", "text": "67", "value": "67"}]},
   {"language": "en", "url": "https://en.wikipedia.org/w/index.php?title=Pension&oldid=2", "values": [{"kind": "number", "text": "70", "value": "70"}]}]}
```

## Decisions
- "Returned a page" = WikiLookup `status: "found"` with a non-null `passage` (`ambiguous`, `no_page` and unknown
  statuses are not pages, consistent with "Clients SHALL treat an unknown status like no_page").
- Two found passages → `agree` or `discrepancy`; exactly one → `gap`; none, or a single-wiki claim → `null`.
- Values are compared as **sets** of normalized values (`kind` + `value`), not counts or positions. A number that
  is part of a recognised date is only a date value. A standalone year is a number. One passage with values and
  the other with none is a `discrepancy` (one side lists its values, the other an empty `values` array).
- Normalization exists so that `1.500` (de) and `1,500` (en), or `2. März 2025` and `2 March 2025`, compare equal.
  Which date and number notations are recognised is backend-local; the shared contract fixes the normalized
  `value` formats and that `text` is a verbatim substring.
- Computed from the WikiLookups of the same run; cached WikiLookups give the same result as fresh ones.
- No LLM, no translation; passages stay unchanged (existing "Passage is verbatim").

## Compatibility classification
| Change | Where used (canonical) | Class |
|---|---|---|
| ClaimLookup `cross_language` (new optional member) | ClaimLookup defined at `openspec/specs/wikipedia-lookup-result/spec.md:114-119`, used only in WikipediaLookup `claims` (`:108-112`); no other spec references ClaimLookup | shared-additive |
| ClaimLookup `cross_language_differences` (new optional member) | same | shared-additive |
| CrossLanguageDifference / ComparedValue objects (new) | new, only in the member above | shared-additive |
No removed or renamed member, no changed type or meaning, no changed status: no shared-breaking change, no client
migration. Existing "ClaimLookup object" already says "at least", and WikipediaLookup says clients ignore unknown
members (`:108`). The "exactly one WikiLookup" in "Single English search" (`:56`) is a count, not an object-shape
clause, and is left unchanged.

## Clients
- backend: producer.
- frontend: first reader (new display in this feature). Older frontends ignore the members.
