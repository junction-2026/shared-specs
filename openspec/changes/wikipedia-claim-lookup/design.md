# Design: Wikipedia claim lookup

Based on backend @ 2f661630a36fc9d7130872162bf86e1456a15fbd, frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ fa8280bcd348502c3e84d6b4a6ebdcd913f03c75.

## Context
- Claims come from `topic_extraction` (topic-extraction-result "Claim object": `text`, `language`, `query`,
  `query_en`, `entities`, `check_worthiness`; claims ordered by `check_worthiness` descending).
- The source language comes from the `translation` result's `source_language`, read the way `news_search` reads it
  (backend `internal/adapter/news_search.go` `readSourceLanguage`: lower-cased, two-letter code or unknown).
- Claim qualification mirrors fact-check-result "Qualifying claims" (min 0.4, max 3, `claims` order).

## Decisions
1. **Separate capability `wikipedia-lookup-result`.** Like every other analyzer result (`news-search-result`,
   `fact-check-result`), the object is consumed by clients through `AnalyzerRun.result`, so it is a shared interface.
2. **Wiki language from `translation`, not from the Claim `language`.** The issue fixes this; it also makes an
   English post search once (`source_language: en`). An unknown or non-two-letter source falls back to `en` only, so a
   bad code never produces a request to a non-existent wiki.
3. **Search mode is deterministic** (digit in the claim text → number/date; no non-numeric entity → event; both
   `fulltext`, otherwise `title`). No LLM call, so the result is reproducible and cacheable.
4. **Page selection and disambiguation use the search hits as candidates**, one search per WikiLookup plus the page
   requests for the chosen hit. A disambiguation top hit is resolved only by an entity-title match among the other
   hits; otherwise `ambiguous` with no page (issue: "do not choose a page").
5. **Passage verbatim.** Lead for `title` mode, search snippet for `fulltext` mode (it shows the matching number or
   date). Wikipedia returns snippets with highlight markup; removing tags and decoding character references is the
   only change allowed, stated in the spec. A long lead may be cut to a leading part (still a verbatim prefix).
6. **All-or-nothing failure.** The issue requires the analyzer to be unavailable on any Wikipedia error, unlike the
   partial-failure rules of `news_search`/`fact_check`. This guarantees no partial, possibly misleading lookup.
7. **Cache is persistent** (survives restart) and keyed by `(language, normalised query, search_mode)`; the mode is
   part of the key because the same query yields a different passage source. Misses (`no_page`, `ambiguous`) are
   successful answers and are cached; failures are not. Storage location and TTL are backend-local.
8. **Category `fact_check`**: it supports checking claims, like `fact_check`; `category` is free text for clients.

## Interface classification (common rule 13, tolerant reader)
| Change | Class | Evidence |
|---|---|---|
| New analyzer id `wikipedia` with a new AnalyzerRun `result` object | shared-additive (new capability) | analysis-jobs-api `openspec/specs/analysis-jobs-api/spec.md:74` (`result` is the service's JSON object verbatim; any analyzer id) |
| Skip reason `no_checkable_claims` reused for `wikipedia` | shared-additive (existing reason, new analyzer) | `openspec/specs/analysis-jobs-api/spec.md:355-357` already maps it to `not_applicable` and a fixed note; no new reason |
| `failed`/`adapter_error`, `timeout`, `cancelled` | no change | `openspec/specs/analysis-jobs-api/spec.md:81` (codes "include"), `:374-375` (Unavailable runs) |
| `GET /api/v1/analyzers` lists one more item | shared-additive | `openspec/specs/analysis-jobs-api/spec.md:181` (items "at least" members; no fixed list) |

No existing object, member, status code or error code is removed, renamed or re-typed: **no shared-breaking change,
no client migration**. Clients that do not know `wikipedia` ignore the AnalyzerRun as with any other unknown analyzer.
Objects are specified as "at least these members"; `status`, `search_mode` and `passage_source` value lists
"include" their values, and clients treat an unknown `status` as `no_page`.

## Ownership (what is not in the shared contract)
Backend-local (backend child `backend-wikipedia-adapter`): MediaWiki API request shape (endpoints, parameters,
`redirects`, `pageprops` for disambiguation), descriptive User-Agent, on-disk cache layout/location/TTL, registry
configuration (`execution.*` keys), example `docs/examples/wikipedia.yaml`, logging and tests.
Frontend: no change in this feature (display is a later feature).

## Overlap with active changes
Only active change on main: `web-page-scraping` (capabilities `analysis-jobs-api` scrape requirements and
`social-scraper-api`). This change modifies neither, so there is no conflict and `base_changes` is empty.

## Risks
- Entity-title matching is strict (equality or `Entity (qualifier)`), so some claims fall back to the top hit; this
  is intended (no guessing), and the passage-level `matched_*` arrays show how relevant the page is.
- Wikipedia rate limits a burst: the backend limits concurrency locally; a 429 after one retry fails the analyzer
  (unavailable), as the issue requires.
