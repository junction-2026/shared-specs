# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Modify `technique-classifier-result`: `explanation_language`, `glossary_version`, `Detection.plain_language`, `TechniqueSpan.why`, presentation
- [x] 1.2 Add `llm-technique-result`: `llm_techniques` analyzer, LlmTechniqueResult, findings, spans, title rule, failures, presentation
- [x] 1.3 Classify affected uses (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-technique-explanations`)
- [ ] 2.1 Versioned glossary artifact (18 + 3 labels, names, definitions, `why` templates) per supported language, English fallback
- [ ] 2.2 `techniques` result members and per-span / per-detection `why`
- [ ] 2.3 `llm_techniques` adapter: prompt, closed labels, exact-substring spans, title rule, confidence minimum, caps, failures, redaction
- [ ] 2.4 Example registry config and finalizer description marking LLM labels as weaker
- [ ] 2.5 Tests with stub LLM and translation results

## 3. Frontend (child `frontend-technique-explanations`)
- [ ] 3.1 Plain-language name, definition and `why` next to highlights, fallback for results without them
- [ ] 3.2 Separate, weaker group for `llm_techniques` findings, title highlights
- [ ] 3.3 Tests including stored older results, markup in strings and unknown labels
