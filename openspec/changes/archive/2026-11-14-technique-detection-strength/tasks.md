# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Modify `technique-classifier-result`: Detection `margin`, `located`, `strength`; TechniqueClassification `summary`; strength rule; compatibility
- [x] 1.2 Modify `analysis-jobs-api` Verdict values meanings
- [x] 1.3 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-technique-detection-strength`)
- [ ] 2.1 Registry: `execution.strong_margin` on `technique_classifier` (number 0 to 1, default 0.15), docs example and README
- [ ] 2.2 Adapter: `margin`, `located`, `strength` per Detection after the span step, `summary`
- [ ] 2.3 `llm.description` of the technique classifier (docs example) explains strength and weak hints
- [ ] 2.4 Finalizer prompt: strong-signal list, three verdict rules, confidence guidance, consistency rule
- [ ] 2.5 Stub-only tests for the parent's acceptance criteria 1 to 5
