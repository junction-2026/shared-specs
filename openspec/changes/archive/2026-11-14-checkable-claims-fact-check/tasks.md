## 1. Shared contract
- [x] 1.1 Delta `topic-extraction-result` (`claims`) and new capability `fact-check-result`
- [x] 1.2 Classify every affected use (design.md), align with active `news-search-result`, validate with `scripts/validate-openspec.sh`

## 2. backend (local change `backend-checkable-claims-fact-check`)
- [ ] 2.1 Extractor: prompt rules and two examples, JSON schema with required `claims`, validation, normalization (clamp, order, cap `max_claims`)
- [ ] 2.2 Engine: adapter-reported skip after `analyzer.started` (reuse project#10's hook if merged)
- [ ] 2.3 `fact_check` adapter: query planning, bounded parallel requests, retry, in-memory cache, flatten/dedupe/sort/cap, rating normalization, credential hiding
- [ ] 2.4 Registry entries; `docs/examples/fact_check.yaml`; `docs/examples/topic_extraction.yaml` with `max_claims`
- [ ] 2.5 Tests with a stub LLM and a stub Fact Check endpoint (no real keys in CI)
