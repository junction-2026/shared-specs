# Proposal: News coverage search analyzer (`news_search`)

## Why

Parent feature junction-2026/project#10. The `topic_extraction` analyzer
(canonical `topic-extraction-result`) names the topics and news items a text refers
to, but nothing looks them up. A `news_search` analyzer searches news and web
coverage of those topics through a search provider (Serper), in the text's language
and in English, so the LLM finalizer and analysts can see whether and how outlets
report the story. Its result reaches clients through the existing job API and event
stream (`Job.analyzers[].result`, `analyzer.succeeded`), so the result shape and the
new skip reason are an interface that the frontend and later fact-check consumers
build on. That interface is this change.

Based on: backend @ f2ee87068d1dbb45352106311c1c93a377bc7dad (project#9
`topic_extraction` and project#7 `mistral_translation` merged; adapters in
`internal/adapter`, bindings `$analyzers.<id>` in `internal/adapter/adapter.go:69-96`;
no adapter can settle a run as `skipped` today, `internal/engine/run.go:82-135`),
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (health page only, no client of
`/api/v1/jobs`), project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e` is a
placeholder), shared-specs @ 42cc024f2458e09216ae1d9dfbc1d8cc5983abca (active change
`social-media-scrape-input` from project#8).

## What Changes

- **news-search-result** (new capability): the analyzer with id `news_search`; the
  NewsSearch result object (`languages`, `queries`, `articles`, `searches_used`,
  `cached`), SearchQuery and Article objects, the new AnalyzerRun skip reason
  `no_searchable_topics`, partial-failure semantics (failed queries listed, analyzer
  still `succeeded`), whole-analyzer failure codes, credential-free errors, URL
  safety and plain-text rendering for clients.

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
`api-conventions`, `topic-extraction-result`. The skip reason is added on a new
condition to a list the canonical spec already defines as open ("`reason` values
include", `analysis-jobs-api/spec.md:73`), so it is shared-additive and no canonical
requirement is modified. This keeps the change disjoint from the active
`social-media-scrape-input` deltas.

## Decisions for approval

- **Result shape is shared** (same precedent as `topic-extraction-result`): clients
  read it through the job API. Provider choice, Serper request details, caching,
  concurrency, Mistral query translation and registry configuration stay
  backend-local.
- **`date` is the provider's text, not a timestamp.** Serper returns values like
  `"3 hours ago"` or `"Nov 12, 2026"`; the contract does not promise a format.
- **`translation` is a hard dependency when listed.** The issue's registry entry has
  `depends_on: [topic_extraction, translation]`; under the canonical dependency rule
  (`analysis-jobs-api/spec.md:80`) a failed `translation` skips `news_search` with
  `dependency_failed`. A deployment that wants searches without translation omits it
  from `depends_on`; then `source` is dropped from the language list. No optional-
  dependency mechanism is introduced.
- **Runtime skip.** `no_searchable_topics` is decided after the run started, so the
  run emits `analyzer.started` then `analyzer.skipped` (allowed by
  `analysis-job-events/spec.md:41`).
- **No frontend task** (issue non-goal; the frontend has no job view). **No project
  task**: `full-e2e` is a placeholder and CI uses stub Serper/Mistral servers in
  backend tests.
- **One backend task.** Adapter, registry, a narrow engine hook for adapter-reported
  skips, example, README and tests: about 10 files in one area.

## Impact

- backend: new `news_search` adapter (Serper client, Mistral query translation,
  in-memory cache), registry validation, adapter-reported skip, example
  `docs/examples/news_search.yaml`, README section, stub-server tests.
- frontend, project: no change.
