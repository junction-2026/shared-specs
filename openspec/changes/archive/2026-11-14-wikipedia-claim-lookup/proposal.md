# Wikipedia claim lookup (junction-2026/project#29)

## Why
For each checkable claim a reader wants to see what the encyclopedia currently says about it, in the language of
the post and in English, with a link that opens the exact revision that was read. Existing analyzers find
fact-checks (`fact_check`) and news coverage (`news_search`) but no reference text.

## What changes
- New regular analyzer `wikipedia` (category `fact_check`, `depends_on: [topic_extraction, translation]`) that
  searches Wikipedia for at most 3 claims with `check_worthiness` >= 0.4, in `{source_language}.wikipedia.org`
  (Claim `query`) and `en.wikipedia.org` (Claim `query_en`), once when the source language is English.
- New shared capability `wikipedia-lookup-result`: the WikipediaLookup result object (per claim, per wiki: a
  revision-pinned page with a verbatim passage and the claim's entities and numbers found in it, or `no_page` /
  `ambiguous` with the query sent), skip and failure semantics and rendering rules, in tolerant-reader style.
- Reuses the existing skip reason `no_checkable_claims` (analysis-jobs-api "Nothing-to-check skips"); no existing
  object, endpoint or error code changes.

Interface only (common rule 13): the MediaWiki request shape, User-Agent, on-disk cache layout, registry
configuration and tests are backend-local requirements of the backend task.

## Impact
- Shared capability added: `wikipedia-lookup-result`. No modified shared capability.
- backend: new adapter, registry entry and example `docs/examples/wikipedia.yaml`, on-disk cache, tests.
- frontend: no change required; display of the result is a later, separate feature. Clients that do not know the
  analyzer ignore the AnalyzerRun as today.

Based on backend @ 2f661630a36fc9d7130872162bf86e1456a15fbd, frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ fa8280bcd348502c3e84d6b4a6ebdcd913f03c75.
