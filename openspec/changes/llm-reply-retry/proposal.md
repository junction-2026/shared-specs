## Why

The `llm` adapter (finalizer `final_synthesis` and `topic_extraction`) fails the whole call with `invalid_output` when the model's reply is cut off (`finish_reason: length`), is not valid JSON, or does not match the schema. For the finalizer the job then ends with no verdict. A benchmark on 2026-11-14 saw 1 failure in 8 calls, a reply cut off at `max_tokens` on a Russian post (junction-2026/project#25). The backend will retry such a reply once. Clients need to see whether a result came from a retry, and what `usage` means when two requests were made.

Based on backend @ 34e1c514854bb0d191b70c2a8bfef83333326959, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 6d1e0c05eeee99ea3099ca5c00e6e8a7c8e16dad.

## What Changes

- `analysis-jobs-api`: FinalAssessment gets two new members, `attempts` (integer or null) and `retry_reason` (string or null). This is additive.
- `analysis-jobs-api`: FinalAssessment `usage` is the sum of the provider's usage reports across both attempts when the `llm` finalizer retried.
- `analysis-jobs-api`: the insufficient-evidence assessment lists the new members as null. Its object listing is rewritten in the "at least" style.
- `analysis-jobs-api`: new requirement "LLM reply retry" defines when a finalization result has `attempts: 2`, the `retry_reason` values (`length`, `invalid_json`, `schema`), and that refusals and provider errors are not retried. A finalization that still fails after the retry fails with `invalid_output` as it does today.
- `topic-extraction-result`: TopicExtraction gets the same `attempts` and `retry_reason` members and the same `usage` summing. The "Extra members dropped" scenario, which listed the stored result exactly, now says "at least". The retry rule applies to `topic_extraction` too.
- No new endpoint, error code or status. No change to the HTTP 429/5xx retry. No change to `http_sync`/`http_async` finalizers apart from the new null members.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `analysis-jobs-api`: FinalAssessment object, insufficient-evidence object, new "LLM reply retry" requirement.
- `topic-extraction-result`: TopicExtraction object, output normalization, new "Topic extraction reply retry" requirement.

## Impact

- backend: adds the reply-level retry to the `llm` adapter (`internal/adapter/llm.go`), new registry settings `retry_invalid_output`, `retry_max_tokens`, `retry_model` and `retry_min_remaining`, the new result members, summed usage, logging and stub-only tests. The registry config format is backend-internal (only backend reads `config/analyzers*.yaml`), so it is specified in the backend's local change, not here.
- frontend: no change required. At 1abe19a, `frontend/src` reads neither `usage` nor `produced_by`/`input_truncated`, and clients ignore unknown members.
- project: no change. No integration suite stubs the LLM provider's reply content.
