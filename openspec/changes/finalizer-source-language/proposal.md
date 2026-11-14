## Why

The finalizer writes `user_text` "in the language of the content" but gets no explicit language signal. When content was translated, or analyzer outputs are in English, the model may answer in the wrong language (e.g. English for a Russian article). The `translation` analyzer already yields `source_language` (ISO 639-1 or null), and other adapters read it; the finalizer does not. Parent: junction-2026/project#63.

For `http_sync` / `http_async` finalizers, request inputs come from binding sources defined in the shared `analyzer-service-protocol` capability, so exposing the language to external finalizer services is a shared interface change. The `llm` finalizer's prompt assembly is backend-internal and lives in the backend's local `analysis-finalizer` change.

## What Changes

- **analyzer-service-protocol** (shared-additive): new job-wide binding source `$job.source_language`: the lower-cased two-letter `source_language` of the job's succeeded `translation` run, or `null` when unknown. Allowed only on `after_all_analyzers_settled` analyzers (like `$job.analyzers` / `$job.coverage`). Existing bindings, request body, finalizer response, validation and normalization are unchanged.
- Backend (local, not in this change): the `llm` finalizer adds a `<source_language>` element to the user message and the default prompt tells the model to write `user_text` in that language.

Non-goals: verdict logic, the FinalAssessment shape, frontend changes, post-hoc translation of `user_text`.

## Impact

- Shared capability: `analyzer-service-protocol` (Requirement "Job-wide binding sources").
- Backend: binding resolution (`internal/adapter/adapter.go`), binding validation (`internal/registry/registry.go`), finalizer prompt assembly (`internal/adapter/llm.go`, `internal/finalizer/finalizer.go`), `config/finalizer/prompt.md`, local spec `analysis-finalizer`.
- Frontend: none. External finalizer services: may opt in by binding the new source; existing configurations behave as before.

Based on backend @ c1d660fc03f70ec8ae995a4e24dd8229c7e2265d, frontend @ 108bbf79cdf415c814f077dc112090257cde0a19, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 197c3a52651e6b726f45f3b46982e81fdaedb5d7.
