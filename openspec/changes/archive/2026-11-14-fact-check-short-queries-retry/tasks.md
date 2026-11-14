# Tasks

## 1. Shared contract
- [ ] 1.1 Review and approve the delta specs for topic-extraction-result and fact-check-result
- [ ] 1.2 Publish the change on shared-specs main (no archive until integration)

## 2. backend (child task backend-fact-check-short-queries-retry)
- [ ] 2.1 Extractor prompt: 2-4 word query rules, plan/decision claims, new examples
- [ ] 2.2 fact_check adapter: one shorter retry per empty search, `retry_of`, ordering, accounting, caching
- [ ] 2.3 Tests with stub LLM and stub provider, no real keys
