## Why
junction-2026/project#11: `topic_extraction` only returns broad topics, which are poor search terms for existing fact-checks. Clients and the LLM finalizer need short, checkable claims and the fact-checks already published about them (Google Fact Check Tools, ClaimReview).

Based on backend @ 8ddabbd3405c2169a776d49af0da4b10ff6fb334, frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 606cc9356f539952b9c63f2004353aa3c388a452 (includes the active change `news-search-result` of project#10, which runs in parallel with this one).

## What Changes
- `topic-extraction-result` (modified): the TopicExtraction object gains a `claims` array of Claim objects (`text`, `language`, `query`, `query_en`, `entities`, `check_worthiness`), ordered by `check_worthiness` descending and capped by the deployment. A model reply without `claims` fails with `invalid_output`. Additive for clients (tolerant reader); readers treat a missing `claims` as `[]`.
- `fact-check-result` (new capability): analyzer `fact_check` (depends on `topic_extraction`), its FactCheckResult object (`queries`, `fact_checks`, `requests_used`, `cached`), Query objects with per-query `status`/`error`, the FactCheck item with a verbatim `rating` and `rating_normalized` (`false | misleading | mixed | true | unrated`), the runtime skip reason `no_checkable_claims`, failure codes, credential hiding and rendering rules.

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`, `api-conventions`, `news-search-result`. Like `news-search-result`, the skip reason is defined in the new capability on a new condition; the canonical list is open ("`reason` values include", `analysis-jobs-api/spec.md:81`), so no canonical requirement there is modified and this change stays disjoint from project#10's deltas.

Not in this change (backend-local, see the backend task): extractor prompt and JSON schema text, registry keys and defaults (`max_claims`, `min_check_worthiness`, `page_size`, `max_age_days`, `max_results`, `max_concurrency`, `cache_ttl`, `timeout`), the in-memory cache, retry backoff, the full rating term table, the finalizer `llm.description`, docs examples and tests.

## Capabilities
### New Capabilities
- `fact-check-result`: result of the `fact_check` analyzer as clients read it from the job API and event stream.

### Modified Capabilities
- `topic-extraction-result`: adds `claims`.

## Impact
- backend: extractor output, new `fact_check` adapter, adapter-reported runtime skip (the same engine hook project#10's `backend-news-search` adds; whichever merges second reuses it).
- frontend: no change; it does not read job results (no reference to `topic_extraction` or `/api/v1/jobs` in frontend @ 3e51ec4).
- project: no change; `full-e2e` is a placeholder and backend tests use stub servers.
- Readers of `topic_extraction`, including project#10's `news_search` (reads only `topics` and `news`), keep working.
