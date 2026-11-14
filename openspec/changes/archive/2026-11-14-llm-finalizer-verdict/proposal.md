# Proposal: LLM finalizer verdict and user-facing text

## Why

Parent feature junction-2026/project#6 replaces the finalizer's external `http_sync`
synthesis service with an LLM called through an OpenAI-compatible
`/chat/completions` API. The LLM returns a three-way verdict about propaganda or
manipulation, its confidence in that verdict and a plain-language text for the
user. The canonical FinalAssessment (four risk verdicts, `overall_score`,
`categories`, `explanation`, `evidence`, `limitations`) does not fit that output,
and no client uses it yet, so the shared contract is replaced now, before any
client builds on it.

Based on: backend @ 554a94522e789f454271ca08ac72b5db6d24af3d, frontend @
3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (does not read `finalization.result` or
`finalization.verdict`), project @ 441ecbf96961128099af004da50a063f18b3345c
(`full-e2e` is a placeholder), shared-specs @
8d3a6d7cfeef2ae2fc100d6bbd9b5adee795837b (no active changes).

## What Changes

- **analysis-jobs-api**
  - **BREAKING** FinalAssessment becomes `{verdict, confidence, user_text,
    produced_by, usage}` with verdicts `detected`, `not_detected`, `uncertain`.
    `overall_score`, `categories`, `explanation`, `evidence` and `limitations` are
    removed, together with the FinalCategory, EvidenceRef and Limitation objects.
  - New requirements "Verdict values" (unknown values read as `uncertain`),
    "Confidence semantics" (replaces "Overall score semantics") and "User text
    rendering" (clients show `user_text` as plain text).
  - The insufficient-evidence short-circuit returns `verdict: uncertain`,
    `confidence: null`, and also applies when none of the analyzers the finalizer
    is configured to receive succeeded.
  - New requirement "Finalization errors hide credentials": `error.message` never
    contains credentials.
  - The analyzers listing gains a scenario that the LLM finalizer's `base_url`,
    `api_key` and `model` are never exposed (rule unchanged).
- **analyzer-service-protocol**
  - **BREAKING** "Finalizer response" and "Finalizer response validation" describe
    the new output for any adapter, including the `llm` adapter; new requirement
    "Finalizer output normalization" (absent `confidence` → null, `usage` from the
    adapter only, other output members dropped).
  - "Analyzer result conventions" no longer mentions EvidenceRef citations.

Not shared (backend-local, see the backend child): the `llm` adapter wire format
towards the provider (`/chat/completions` request, `response_format` modes,
headers, `extra_body`, retries), the registry `llm` block on analyzers, the prompt
file and its assembly, startup checks, logging and tests. The LLM provider is an
outside service, not a repository of this project, and no other repository can
call or configure the adapter.

## Impact

- Clients: none read the old shape (frontend @ 3e51ec4 has no reference to
  `finalization.result` or the JobSummary `finalization.verdict`). Clients written
  from now on use the new shape.
- External finalizer services on `http_sync`/`http_async`: must return the new
  output. None is deployed (the live finalizer is `not_configured`).
- Backend: implements the new contract and the `llm` adapter (one child task).
