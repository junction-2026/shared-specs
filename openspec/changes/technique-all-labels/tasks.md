# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Merge shared-specs main (archived #17 `technique-spans`) and rebase the delta onto it
- [x] 1.2 Delta for `technique-classifier-result` (ADDED/MODIFIED/REMOVED requirements), keeping every #17 span requirement
- [x] 1.3 Classify every affected use with spec file:line evidence (design.md)
- [x] 1.4 Validate with `scripts/validate-openspec.sh`
- [ ] 1.5 On archive: rewrite the capability's Purpose as stated in design.md

## 2. Backend (child `backend-technique-all-labels`)
- [ ] 2.1 Registry: `technique` and `social` model blocks (endpoint, headers, cutoff), `social_max_words`, `technique_min_words`; reject `short`/`long`/`threshold`/`thresholds`/`short_max_words`/`max_sentences` with a message naming the replacement; `spans` block unchanged
- [ ] 2.2 Routing and one request per selected model carrying only `translated_text`; sentence batches removed
- [ ] 2.3 Response validation; unknown labels kept; `results` (ModelResult/TechniqueScore) and `detected` (known labels above cutoff in any model, `models`, no `score`) output; span step fed the new `detected`
- [ ] 2.4 Example YAML with new `llm.description`; README; local specs `analyzer-adapters`, `analyzer-registry`
- [ ] 2.5 Stub-service tests (routing bounds, cutoff equality, unknown labels, no averaging, partial failure, non-English job, span tests still green); `propaganda_detection` tests unchanged
