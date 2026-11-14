## 1. Shared contract

- [ ] 1.1 Add the AnalyzerRun availability requirements to analysis-jobs-api (this change)
- [ ] 1.2 Validate with `scripts/validate-openspec.sh`

## 2. backend (child task `backend-analyzer-availability`)

- [ ] 2.1 Mapping function + table-driven unit test covering every reason in the delta spec and an unknown reason
- [ ] 2.2 Set `availability`/`note` on every AnalyzerRun when it settles; expose in REST and events
- [ ] 2.3 Add `availability`/`note` to LLM finalizer entries; update `config/finalizer/prompt.md`
- [ ] 2.4 Stub-only tests for the parent issue acceptance criteria 2-5
