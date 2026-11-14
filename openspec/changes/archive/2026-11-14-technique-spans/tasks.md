# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Modify `technique-classifier-result`: TechniqueClassification span members, Detection `spans`, TechniqueSpan, sentence and phrase methods, failure isolation, presentation
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-technique-spans`)
- [ ] 2.1 Registry: sentence model (`nci-social`) and span LLM settings, span deadline and caps, startup validation
- [ ] 2.2 English: split `Job.input.content` into sentences with UTF-16 offsets, one batch to the sentence model, spans per detected technique
- [ ] 2.3 Other languages: LLM candidate phrases, exact substring acceptance, leftmost-occurrence offsets, dedup, cap
- [ ] 2.4 Result members `span_method`, `span_status`, `spans_truncated`, `detected[].spans`; failure isolation; credential redaction
- [ ] 2.5 Tests with stub services, including non-ASCII and non-BMP offsets

## 3. Frontend (child `frontend-technique-spans`)
- [ ] 3.1 Job result view for `?job=<id>` reading `GET /api/v1/jobs/{id}`
- [ ] 3.2 Plain-text rendering of `Job.input.content` with span highlights per technique; empty-span techniques listed without highlight
- [ ] 3.3 Tests including markup in content, overlapping spans and non-BMP offsets
