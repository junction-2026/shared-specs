## 1. Shared contract

- [ ] 1.1 Publish the `analysis-jobs-api` and `topic-extraction-result` deltas (this change)

## 2. Backend (child task backend-llm-reply-retry)

- [ ] 2.1 Reply-level retry in the `llm` adapter for `length`, invalid JSON and schema/built-in-check failures; no retry for refusals, `content_filter` or provider 4xx other than 429
- [ ] 2.2 Registry settings `retry_invalid_output`, `retry_max_tokens`, `retry_model`, `retry_min_remaining` (backend local spec)
- [ ] 2.3 `attempts`, `retry_reason` and summed `usage` on FinalAssessment and TopicExtraction; null for orchestrator-produced and http finalizer results
- [ ] 2.4 Stub-only tests for every scenario of this change and the backend's local change

## 3. Frontend

- [ ] 3.1 None required (members are ignored by tolerant readers)
