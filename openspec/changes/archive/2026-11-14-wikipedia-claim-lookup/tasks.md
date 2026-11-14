## 1. Shared contract
- [x] 1.1 Add capability `wikipedia-lookup-result` (WikipediaLookup, ClaimLookup, WikiLookup objects, selection,
      skip, failure, cache counters, rendering).
- [x] 1.2 Classify the change against existing shared specs (design.md: additive only).

## 2. backend (child task `backend-wikipedia-adapter`)
- [ ] 2.1 `wikipedia` adapter kind, registry validation and `docs/examples/wikipedia.yaml`.
- [ ] 2.2 Claim selection, wiki languages, search mode, page selection, disambiguation, passage and matches.
- [ ] 2.3 On-disk cache under the backend data directory; counters `requests_used` and `cached`.
- [ ] 2.4 Failure handling (`adapter_error`, `timeout`, `cancelled`), descriptive User-Agent.
- [ ] 2.5 Offline tests with recorded MediaWiki fixtures for every scenario of the capability.

## 3. Publication
- [ ] 3.1 Archive this change into `openspec/specs/wikipedia-lookup-result/` when the feature integrates.
