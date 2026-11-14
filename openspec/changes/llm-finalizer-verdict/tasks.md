# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Replace FinalAssessment and its semantics in `analysis-jobs-api`
- [x] 1.2 Replace finalizer response and validation in `analyzer-service-protocol`
- [x] 1.3 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-llm-finalizer`, separate repository)
- [ ] 2.1 Implement the new FinalAssessment normalization, validation and short-circuit
- [ ] 2.2 Implement the `llm` adapter, registry `llm` block, prompt file and startup checks
- [ ] 2.3 Stub-endpoint tests for the acceptance criteria; docs example
