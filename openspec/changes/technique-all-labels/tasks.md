# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Delta for `technique-classifier-result` (MODIFIED/ADDED/REMOVED requirements)
- [x] 1.2 Classify every affected use with spec file:line evidence (design.md)
- [x] 1.3 Validate with `scripts/validate-openspec.sh`
- [ ] 1.4 On archive: rewrite the capability's Purpose as stated in design.md

## 2. Backend (child `backend-technique-all-labels`)
- [ ] 2.1 Registry: `technique` and `social` model blocks (endpoint, headers, cutoff), `social_max_words`, `technique_min_words`; reject old keys
- [ ] 2.2 Routing and one request per selected model with only `translated_text`; no `job_content` input
- [ ] 2.3 Response validation; unknown labels kept; TechniqueClassification/ModelResult/TechniqueScore output
- [ ] 2.4 Example YAML with new `llm.description`; README; local specs `analyzer-adapters`, `analyzer-registry`
- [ ] 2.5 Stub-service tests; `propaganda_detection` tests unchanged
