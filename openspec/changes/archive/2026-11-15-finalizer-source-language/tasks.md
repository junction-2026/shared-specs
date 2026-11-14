## 1. Shared contract

- [ ] 1.1 Publish `$job.source_language` in `analyzer-service-protocol` (this change).

## 2. Backend (junction-2026/backend, local change `finalizer-source-language`)

- [ ] 2.1 Resolve and validate the `$job.source_language` binding source (after_all only).
- [ ] 2.2 Add `<source_language>` to the `llm` finalizer user message when known; update `config/finalizer/prompt.md`.
- [ ] 2.3 Tests: non-English language in prompt, `en`, missing/failed/null translation, HTTP binding value and registry rejection on other triggers.
