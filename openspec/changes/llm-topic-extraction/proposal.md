# Proposal: LLM topic and news extraction analyzer

## Why

Parent feature junction-2026/project#9. A later fact-check step has to know *what*
to check in a submitted text. An LLM-based analyzer extracts fact-checkable
**topics** (with a search query) and the **news** items the text refers to. Its
result reaches clients through the existing job API and event stream
(`Job.analyzers[].result`, `analyzer.succeeded`), so the result shape is an interface
that the frontend and future fact-check consumers build on. That shape is this
change.

Based on: backend @ 20183d6d94cc4d3876916e551aab9c0cdd029bd9 (Go orchestrator with
the `llm` adapter restricted to the finalizer: `internal/registry/registry.go:364-366`,
`internal/adapter/adapter.go` returns "the llm adapter runs only as the finalizer";
project#7 `mistral_translation` merged), frontend @
3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (health page only, no client of
`/api/v1/jobs`), project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e` is a
placeholder), shared-specs @ 7885bffdf154823a03961f0fb8dc0349d770752e (active change
`social-media-scrape-input` from project#8).

## What Changes

- **topic-extraction-result** (new capability): the result object of the topic
  extraction analyzer (id `topic_extraction`): `topics` (`title`, `query`,
  `description`), `news` (`headline`, `summary`), `input_truncated`, `usage`; validation (invalid model
  output fails only this analyzer with `invalid_output`), output normalization,
  empty lists as a valid outcome, plain-text rendering of model output, credential-free
  error messages, and that it is an ordinary selectable analyzer.

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
`api-conventions`. The analyzer is one more registry analyzer; every existing
request, response and event stays as it is. No existing canonical requirement is
modified, so this change does not overlap the active `social-media-scrape-input`
deltas.

## Decisions for approval

- **Result shape is shared**, because clients read it through the job API and a
  future fact-check feature consumes it. LLM configuration (env vars, prompt, adapter
  reuse) stays backend-local.
- **No frontend task.** The frontend has no job view or submission form yet
  (`frontend/src` has only the health page); showing topics/news needs that view
  first and is left to a later feature. The issue marks the display optional.
- **Parallel with project#8** (`social-media-scrape-input`, implementing): no shared
  requirement of that change is modified; scrape jobs feed the analyzer through the
  ordinary `Job.input`. Backend-local rules keep the two features' files and
  `backend/analyzer-registry` requirements disjoint (design.md decision 9).
- **Bounded input** (`input_truncated`): scraped profile history can be up to 100
  posts, so the backend cuts long content (default 20000 characters) and says so.
- **One backend task.** Registry, adapter, prompt, example, README and tests touch
  about 10 files in one area.

## Impact

- backend: `adapter: llm` allowed on regular analyzers with the built-in
  `topic_extraction` task, new prompt `config/extractor/prompt.md`, example
  `docs/examples/topic_extraction.yaml`, README section, mock-LLM tests.
- frontend, project: no change.
