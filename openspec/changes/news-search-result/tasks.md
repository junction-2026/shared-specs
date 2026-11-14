# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add capability `news-search-result`
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-news-search`)
- [ ] 2.1 Registry: `adapter: news_search`, its execution keys and defaults, bindings `topics` / `translation`, startup validation
- [ ] 2.2 Adapter-reported skip (`no_searchable_topics`) settled after `analyzer.started`
- [ ] 2.3 Query building (limits, language resolution, one Mistral translation request per target language)
- [ ] 2.4 Serper news search with web fallback, bounded concurrency, single retry of 429/5xx, 401/403 abort, in-memory TTL cache
- [ ] 2.5 Merging (URL dedup, per-domain and total limits, ordering) into the NewsSearch object; partial failures
- [ ] 2.6 Credential redaction; `docs/examples/news_search.yaml`; README section
- [ ] 2.7 Tests against stub Serper and stub Mistral servers (no real keys)
