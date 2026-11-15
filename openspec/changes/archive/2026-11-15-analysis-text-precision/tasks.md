## 1. Shared contract
- [ ] 1.1 Review and approve the analysis-jobs-api, llm-technique-result and topic-extraction-result deltas
- [ ] 1.2 Publish to shared-specs main without archive

## 2. backend (local change backend-analysis-text-precision)
- [ ] 2.1 Finalizer prompt: classifier as supporting evidence, bot_detection rule, output language, plain language, posts and articles
- [ ] 2.2 `propaganda_detection` `llm.description` (server config and docs/examples) matches the prompt
- [ ] 2.3 Finalizer request always carries `<source_language>code (Name)</source_language>`
- [ ] 2.4 `user_text` language check and soft reply retry with the language `retry_reason`
- [ ] 2.5 `llm_techniques` prompt definition and examples; default `min_confidence` 0.6
- [ ] 2.6 Extractor prompt: specific queries, one assertion per claim, group generalisations check-worthy
- [ ] 2.7 Tests with fakes and stubs; bot_detection and risk score untouched (diff check)
