## Context

Based on backend @ 2f661630a36fc9d7130872162bf86e1456a15fbd, frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ fa8280bcd348502c3e84d6b4a6ebdcd913f03c75.

Today (backend `internal/engine/run.go`) every `analyzer.*` event carries only `{analyzer: AnalyzerRun}` (run.go:83, :101, :204), `analysis.finalizing` only `{finalization}` (run.go:159), `scrape.started` only `{scrape}` (scrape.go:16), and `job.snapshot` only `{job}` (analysis-job-events spec.md:23). The registry (`internal/registry/registry.go:277`) has no UI settings. The frontend at d590b92 has no WebSocket client (`grep -rn "/events\|job.snapshot" frontend/src` is empty).

## Goals / Non-Goals

Goals: a client can show the plan, the current activity in user terms, progress, and compact previews (incl. technique explanations and highlightable spans) as each analyzer finishes, and rebuild all of it from `job.snapshot` alone.

Non-goals: per-event LLM or translation calls; server-side localization of UI text; exposing full results, raw provider data, prompts or keys in previews; merging `llm_techniques` into `techniques`; any change to `GET /api/v1/jobs/{id}` or the Job object; frontend consumption (follow-up feature).

## Decisions

1. **Delta in `analysis-job-events`, not `analysis-jobs-api`.** The issue asks for the documentation in `analysis-jobs-api`, but all event types and members are specified in `analysis-job-events` (spec.md:33-112); putting them there keeps one owner per concept. No requirement of `analysis-jobs-api` changes.
2. **Snapshot members beside `data.job`, not inside it.** "Event and REST consistency" (analysis-job-events spec.md:61-62) requires `data.job` to equal the REST Job. Adding `preview` to AnalyzerRun would either change `GET /jobs/{id}` (acceptance criterion 8 forbids that) or break the consistency rule. So `plan`, `progress`, `previews` (map by analyzer id) and `activities` sit next to `data.job`.
3. **Plan membership.** Planned = AnalyzerRuns not skipped as `disabled`/`not_selected` and not hidden, plus the finalizer only when finalization will run (an enabled finalizer and `options.finalize` true). Then `progress.done` reaches `total - 1` exactly when `analysis.ready_for_finalization`/`analysis.finalizing` happen, and reaches `total` when finalization ends; with no finalizer it reaches `total` at the barrier. `not_applicable` and later skips stay planned and count as done.
4. **Plan timing.** Text jobs: right after `job.started`, before the creation-time `analyzer.skipped` events (which existing spec.md:41 places "right after `job.started`"; they still follow it, only with `analysis.planned` in between). Scrape jobs: right after `scrape.succeeded`, before the `not_applicable` skips. For scrape jobs the `disabled`/`not_selected` skips are emitted before the plan exists; they are unplanned and carry no `progress`. A failed scrape never gets a plan. Hence "`progress` on every settle event emitted after `analysis.planned`".
5. **Hidden analyzers.** `text_stats` is hidden by default (it is a statistics helper, not a user-facing check). Hiding is a deployment registry setting (backend-local `ui.hidden`), so the shared contract only says "the deployment marks as hidden; `text_stats` by default".
6. **Activity = key + English fallback + structured params.** The issue gives `key`, `text`, `detail`. `detail` is an English phrase; a client that localizes from `key` would otherwise have to parse `detail` to localize it. `params` carries the same facts structured (`languages`, `claims`, `models`, `title_checked`, `host`) so a client localizes both parts without parsing. `text`/`detail` follow the "note" convention of analysis-jobs-api (spec.md:348-349): fixed English, not parsed, wording may change.
7. **Scrape detail = host.** The issue says "platform or domain". The host of the requested URL is known before the scrape runs for every URL kind (social posts and, with the active `web-page-scraping` change, web pages); the platform is not known before recognition for pages. `params.host` is lower-case without leading `www.`.
8. **Preview selection rules** are deterministic so backend tests and future clients agree: `techniques` sorted by the best above-cutoff score of the label (a Detection carries no score of its own, technique-classifier-result Detection object), `llm_techniques` by `confidence`, others in result order. `*_total` counters tell a client that the list was cut. Unknown/foreign analyzers get `preview: null`; a malformed result gives null members, never a failed run.
9. **Untrusted text.** `techniques` texts come from the fixed glossary; `llm_techniques.explanation`, `topic_extraction` claim texts and topic titles are model output already present in the full result and are passed on unchanged; everything is plain-text rendered. Nothing else derived from model output, no provider payloads, prompts, usage or keys.

## Compatibility classification

Every endpoint and object touched, with canonical evidence (shared-specs @ fa8280b):

| Change | Where used today | Class |
|---|---|---|
| New event type `analysis.planned` | Envelope: clients MUST ignore unknown `type`s (analysis-job-events spec.md:16) | shared-additive |
| `analyzer.started` + `activity`, `progress` | Analyzer events, `data.analyzer` (analysis-job-events spec.md:34) | shared-additive (new members) |
| `analyzer.succeeded` + `progress`, `preview`; `analyzer.failed`/`skipped` + `progress`, `availability`, `note` | spec.md:34, :41; availability/note already on `data.analyzer` (analysis-jobs-api spec.md:338, :393), duplicated at `data` level with equal values | shared-additive |
| `analysis.finalizing` + `activity`, `progress`; `analysis.finalized`/`analysis.finalization_failed` + `progress` | Finalization events (analysis-job-events spec.md:55) | shared-additive |
| `scrape.started` + `activity` | Scrape events (analysis-job-events spec.md:101) | shared-additive |
| `job.snapshot` + `plan`, `progress`, `previews`, `activities` | Snapshot on connect (analysis-job-events spec.md:23); `data.job` unchanged, so Event and REST consistency (spec.md:62) still holds | shared-additive |
| Event ordering: `analysis.planned` between `job.started` and creation-time skips | spec.md:41 ("right after `job.started`"), spec.md:101 (`scrape.started` right after `job.started`, unchanged) | shared-additive: a new event type in between, which existing clients ignore; no existing relative order changes |
| Job, AnalyzerRun, Coverage, Finalization objects, `GET /api/v1/jobs/{id}`, `GET /api/v1/jobs`, `GET /api/v1/analyzers` | analysis-jobs-api spec.md:44-195 | unchanged |
| Result objects (TechniqueClassification, LlmTechniqueResult, NewsSearch, FactCheckResult, SourceInfo, TopicExtraction) | their result capabilities | unchanged; only read to build previews |

No shared-breaking change. Affected clients: none today (frontend has no WebSocket consumer at d590b92); future clients opt in.

No existing requirement uses "exactly" for a member set that this change touches; the new requirements use "at least" for every object.

## Overlap with active changes

`web-page-scraping` (junction-2026/project#26) modifies `analysis-jobs-api` and `social-scraper-api`, not `analysis-job-events`; no delta conflict. Decision 7 is valid for its `web` platform as well. This change does not build on it.

## Risks / Trade-offs

- The `techniques` activity `params.models` repeats the backend's model selection before the adapter runs; if the adapter's selection rules change, both must change together (backend-local, covered by a test).
- `previews` in the snapshot grow with the number of analyzers (bounded: at most 8 planned previews, each capped).
