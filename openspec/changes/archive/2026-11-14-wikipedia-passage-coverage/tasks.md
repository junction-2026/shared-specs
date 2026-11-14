# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Delta `wikipedia-lookup-result`: coverage label, terms, rules (standalone numbers), verbatim evidence, per-WikiLookup scope, recent events, no verdict
- [x] 1.2 Delta `analysis-jobs-api`: FinalAssessment `wikipedia_quotes`, its verification, persistence/interruption (rebased on `main` @ 07b1fce; canonical persistence requirements kept untouched)
- [x] 1.3 Delta `analyzer-service-protocol`: finalizer response and normalization of `wikipedia_quotes`

## 2. backend (child `backend-wikipedia-coverage`)
- [ ] 2.1 Compute `coverage` and `evidence_sentence` per WikiLookup in the wikipedia adapter (incl. cached entries), in `internal/adapter/wikipedia_coverage.go`, independent of other WikiLookups (parallel to #47)
- [ ] 2.2 FinalAssessment `wikipedia_quotes`: verify against the job's `wikipedia` result, drop others, `[]` default; persisted unchanged by the SQLite store across restart, absent when finalization is interrupted
- [ ] 2.3 LLM finalizer schema and prompt: label semantics, quote only via `wikipedia_quotes`, verbatim
- [ ] 2.4 `llm.description` of `wikipedia` (docs/examples/wikipedia.yaml and shipped config) states that an empty list and `no_coverage` mean "not found in Wikipedia", not "false"
- [ ] 2.5 Tests for every scenario of this change
