# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Capability `technique-classifier-result` (revised for junction-2026/project#16)
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-technique-analyzer`)
- [ ] 2.1 Registry: `adapter: technique_classifier`, `technique` / `social` model blocks (endpoint, headers, cutoff), `social_max_words`, `technique_min_words`, `timeout`, startup validation
- [ ] 2.2 Word-count routing; one request per model run; response validation (`invalid_output`)
- [ ] 2.3 TechniqueAnalysis object: all 18 labels per model, unknown labels kept, `cutoff`/`above_cutoff`
- [ ] 2.4 Credential redaction; `docs/examples/technique_classifier.yaml` with `llm` block; README section
- [ ] 2.5 Tests against stub classifier services; `propaganda_detection` tests unchanged
