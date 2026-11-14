# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add capability `topic-extraction-result`
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-llm-topic-extraction`)
- [ ] 2.1 Allow `adapter: llm` on regular analyzers with `execution.task: topic_extraction`; registry validation and own env vars
- [ ] 2.2 Built-in extraction schema, user message with delimited content, validation and normalization into the TopicExtraction object
- [ ] 2.3 Default prompt `config/extractor/prompt.md` shipped in the image; `docs/examples/topic_extraction.yaml`; README section
- [ ] 2.4 Tests against a mock OpenAI-compatible server (success, empty news, invalid output, retry, redaction, timeout, startup errors, finalizer opt-in)
