# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add capability `technique-classifier-result`
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-technique-classifier`)
- [ ] 2.1 Registry: `adapter: technique_classifier`, `short`/`long` model blocks, `short_max_words`, `max_sentences`, `timeout`, startup validation
- [ ] 2.2 Word-count routing, sentence splitter with offsets, one batch request per job, response validation (`invalid_output`)
- [ ] 2.3 TechniqueClassification object: thresholds and overrides, detections, sentences, offset resolution (`original` vs `translation`, UTF-16)
- [ ] 2.4 Built-in display name and explanation map for all 18 techniques
- [ ] 2.5 Credential redaction; `docs/examples/technique_classifier.yaml`; README section
- [ ] 2.6 Tests against stub classifier services (no real endpoint or token)
