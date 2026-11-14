# Proposal: Outlet information result (`source_info`)

## Why

Parent feature junction-2026/project#18. The backend gets a `source_info` analyzer that
looks up the news outlet, political leaning and country behind every article found by
`news_search` (and behind the job's own `input.source.url`) in the static outlet table
`data/outlets.csv`, and summarises the leaning and country mix for the LLM finalizer.
The result reaches clients verbatim through `Job.analyzers[].result` and
`analyzer.succeeded` (`analysis-jobs-api/spec.md:74`), so the result shape, the
analyzer id, its skip reason and the matching rule clients see are an interface
between repositories. That interface is this change.

Based on: backend @ 4b3d394c7dd9a1ddea1f0c4cc96a37afd817ec23 (`data/outlets.csv`
and `data/README.md` from backend#55 are merged; adapter run-time skip
`internal/adapter/news_search_skip.go`; bindings `internal/adapter/adapter.go:79-116`;
triggers `internal/registry/registry.go:26-27`),
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (no job client; renders no
analyzer results), project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e`
only), shared-specs @ 518903a3323a930a2dc357890e4f21df0a4641cb (no active changes).

## What Changes

- **source-info-result** (new capability): analyzer id `source_info`; the SourceInfo
  result object (`articles`, `page_outlet`, `summary`, `table`); SourceArticle,
  Outlet, SourceSummary and OutletTable objects; the host / registered-domain matching
  rule; skip reason `no_sources`; failure codes; plain-text rendering and "context, not
  evidence" presentation rules.

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
`news-search-result` (read only), `api-conventions`. `no_sources` is added the same way
as `no_searchable_topics` (`news-search-result/spec.md`, "Nothing to search"): clients
already treat unknown skip reasons as "not run".

## Decisions for approval

- **Shared: result shape, id, skip reason, matching rule. Backend-local:** CSV loading
  and header/duplicate validation, `execution.outlets_file`, Dockerfile `COPY`, registry
  validation, the LLM description and `docs/examples/source_info.yaml`.
- **Engine semantics kept for a dependency that did not succeed.** The analyzer uses
  trigger `on_dependencies_succeeded` (as in the issue's registry entry), so a failed or
  skipped `news_search` gives the canonical `dependency_failed` / `dependency_skipped`
  and `page_outlet` is not computed in that case, even when `input.source.url` is set.
  `no_sources` applies when `news_search` succeeded with no articles and there is no
  `input.source.url`. The issue allows either reason ("`dependency_failed` or
  `no_sources`"); this avoids a new trigger type.
- **`domain` of a SourceArticle is the normalized host** used for matching
  (`news.bbc.co.uk`), not the outlet's domain (that is `outlet.domain`); null for an
  unparsable URL.
- **`page_outlet` is an Outlet or null** and is not counted in `summary`.
- **Outlet members** limited to `name`, `domain`, `country_code`, `country`, `bias`,
  `factuality` (no `hosts`, `site_lang`), as requested; unknown country is `""`.
- **No frontend task** (not requested; no client renders analyzer results yet).
  **No project task**: no integration suite exercises analyzers; backend tests use a
  test CSV and the real data file.
- **One backend task**.

## Overlapping feature (junction-2026/project#16)

#16 ("Technique analyzer: score all 18 labels", shared change
`technique-classifier-result` on `plan/16-technique-analyzer-score-all-18` @
94884abee2ed6fb7673d0c9830a9dbebaf64e962) runs in parallel and also changes backend
`analyzer-adapters` and `analyzer-registry`.

- **Shared specs: no overlap.** #16 only touches `technique-classifier-result`; this
  change only adds `source-info-result`. Neither modifies `analysis-jobs-api` or another
  canonical capability, so the two changes merge independently in either order.
- **Backend: disjoint files, additive local deltas.** This plan's backend task puts its
  code in new files (`internal/outlets/`, `internal/adapter/source_info*.go`,
  `internal/registry/source_info*.go`) and touches shared files only with one-line
  additions: the adapter constant and `Execute` switch case
  (`internal/adapter/adapter.go:35-50`), the call to its validation from the registry
  normalizer, the new `outlets_file` field on `Execution`, the `Executor` constructor
  wiring, one `Dockerfile` `COPY` line and a README section. Its local OpenSpec change
  uses only `## ADDED Requirements` with `Source info ...` / `Outlet table ...` names and
  does not MODIFY or REMOVE any existing requirement of `analyzer-adapters` or
  `analyzer-registry` (in particular none of the `Technique classifier ...` ones #16
  rewrites). It does not touch `internal/adapter/technique*.go`,
  `internal/registry/technique*.go` or `docs/examples/technique_classifier.yaml`.
- Whichever backend PR merges second rebases; the expected conflicts are adjacent lines
  in the switch / constant blocks and the README, resolved by keeping both.
- No dependency between the two backend tasks: neither imports or calls the other's code.

## Impact

- backend: outlet table loader, `source_info` adapter, registry keys and validation,
  Dockerfile `COPY data/outlets.csv`, `docs/examples/source_info.yaml`, tests.
- frontend, project: no change.
