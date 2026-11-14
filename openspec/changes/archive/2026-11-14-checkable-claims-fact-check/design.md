## Context
Canonical `topic-extraction-result` defines TopicExtraction with "at least" `topics`, `news`, `input_truncated`, `usage` and tolerant readers (`openspec/specs/topic-extraction-result/spec.md:20`). Normalization drops every other member of the reply (`:66`). AnalyzerRun `result` is the analyzer's object (`openspec/specs/analysis-jobs-api/spec.md:74`); skip reasons and error codes are open lists (`:81`). An analyzer that ran may settle as `skipped`: `analyzer.started` only has to precede its settle event (`openspec/specs/analysis-job-events/spec.md:41`).

The active change `news-search-result` (project#10, on main @ 606cc93) adds analyzer `news_search`, which also depends on `topic_extraction`, defines its own runtime skip reason `no_searchable_topics` inside its capability, and reports per-query failures as `status`/`error` on each SearchQuery. Backend @ 8ddabbd has no adapter-reported skip yet (`internal/engine/run.go:111-135` skips only by dependency).

## Goals / Non-Goals
Goals: a contract that lets backend implement and any client consume `claims` and `fact_check` concurrently, consistent with `news-search-result`. Non-goals (parent issue): LLM verdicts or extra LLM calls in `fact_check`, translation calls, pagination (`pageToken`), `reviewPublisherSiteFilter`, a persistent cache, frontend display.

## Compatibility classification
Every use of the touched objects in canonical shared specs and active changes (grep of `topic_extraction`, `TopicExtraction`, `reason`, `AnalyzerRun`):

| Change | Where used | Class |
|---|---|---|
| New member `claims` on TopicExtraction | `topic-extraction-result/spec.md:20` (object), `:23-24` (scenario), `:65-70` (normalization) | shared-additive: new member, clients ignore unknown members (`:20`) |
| TopicExtraction read by `news_search` | `changes/news-search-result/specs/news-search-result/spec.md` ("News search analyzer", "Nothing to search": reads `topics`/`news` only; its scenario result has no `claims` and stays valid as "at least") | unaffected |
| Model reply without `claims` fails `invalid_output` | `topic-extraction-result/spec.md:47-56` | for clients a new cause of an existing code on an existing condition (invalid model reply); additive |
| Claim object, plain-text rendering of Claim strings | `topic-extraction-result/spec.md:86-91` | shared-additive |
| New analyzer `fact_check`, FactCheckResult | new capability; `analysis-jobs-api/spec.md:74` | shared-additive: new analyzer id |
| Skip reason `no_checkable_claims` (runtime, after `analyzer.started`) | `analysis-jobs-api/spec.md:81` ("values include"), `analysis-job-events/spec.md:41` | shared-additive: new value on a new condition, same pattern as `no_searchable_topics` |
| Coverage | `analysis-jobs-api/spec.md:99` | unchanged: the runtime skip counts as applicable, as for `news_search` |
| Query `error.code` `search_failed` | new object | shared-additive; same code name as SearchQuery in `news-search-result` |
| `rating_normalized` values | new | shared-additive; unknown values read as `unrated` so later values stay additive |

No shared-breaking change, no client migration, no "exactly" clause touched. Older backends without `claims` are tolerated by `fact_check` (skip) and by clients (missing `claims` read as `[]`).

## Decisions
- **No delta to `analysis-jobs-api`.** The earlier draft modified "AnalyzerRun outcomes" to list `no_checkable_claims`; dropped to stay disjoint from project#10 and to follow its precedent (reason defined in the new capability, open list).
- **Per-query failures as in `news-search-result`**: each Query has `status`, `cached` and `error` (code `search_failed`), instead of a separate `failed_queries` array. Clients handle both analyzers' query lists the same way.
- **Counter names follow the parent issue** (`requests_used`, `cached`); they mean the same as `searches_used`/`cached` in `news-search-result`.
- **`claims` is required in the model reply but tolerated as missing by readers.** The orchestrator always writes it.
- **Invalid individual claims fail the analyzer** (one validation rule for the reply, as for blank topic queries). `entities` absent/null becomes `[]`; `check_worthiness` outside 0-1 is clamped.
- **Orchestrator orders and caps claims** by `check_worthiness` descending (stable), at most the deployment maximum (default 5).
- **English detection** uses the primary subtag of `language` (`en`, `en-GB`, case-insensitive): one request; other claims send `query` with their `language` and `query_en` with `en`. Identical `(query, languageCode)` pairs across claims are sent once.
- **Failure policy**: 400/401/403 fail the whole analyzer with `adapter_error` (configuration problem). 429/5xx get one retry; remaining failures fail only that query; if every query failed, `adapter_error`.
- **`rating_normalized`**: the shared spec fixes the five values and a minimum term table (acceptance criterion 6); the backend owns the full table.
- **Cache visibility**: the cache is backend runtime; clients see `requests_used`, `cached` and per-Query `cached`.
- **`url` rendering**: only absolute `http`/`https` URLs may become links; all other strings are plain text.

## Risks / Trade-offs
- Provider quota is unpublished: bounded by caps (claims, concurrency) and the 24h cache.
- A match is a similar checked claim, not necessarily the same one: stated in the contract; `for_claim` and `claim` allow comparison.
- Backend overlap with project#10: both add an adapter-reported skip in `internal/engine/run.go` and register an adapter in `internal/adapter/adapter.go`/registry. The backend task reuses project#10's hook when merged first, otherwise adds an equivalent narrow hook (adapter returns a skip reason) that project#10 can reuse; the integration merge resolves the small overlap.
