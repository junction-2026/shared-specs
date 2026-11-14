## Why

The job event stream (`GET /api/v1/jobs/{id}/events`) tells a client only that an AnalyzerRun changed state. A client cannot show what is running in user terms, how far the job is, or anything useful before the final verdict, and full `result` objects are large and internal. junction-2026/project#30 adds a run plan, user-facing activity descriptions, progress counters and compact, safe-to-render previews of each analyzer's result (including the technique explanations of junction-2026/project#27), so a client can build a live progress view and highlight and explain phrases as soon as each analyzer finishes.

Based on backend @ 2f661630a36fc9d7130872162bf86e1456a15fbd, frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ fa8280bcd348502c3e84d6b4a6ebdcd913f03c75.

## What Changes

- New event `analysis.planned` (`data.analyzers` PlanEntry list with `id`, `name`, `activity_key`, `depends_on`, `phase`; `data.total`), emitted right after `job.started` for jobs created with `input` and right after `scrape.succeeded` for jobs created with `scrape`. Hidden analyzers (by default `text_stats`), disabled and unselected analyzers are not planned; the finalizer is planned when finalization will run.
- `analyzer.started` gains `data.activity` (Activity: `key`, `text`, `detail`, `params`) and `data.progress` (Progress: `done`, `running`, `total`).
- `analyzer.succeeded`, `analyzer.failed` and `analyzer.skipped` gain `data.progress`; `failed` and `skipped` also gain `data.availability` and `data.note` (equal to the AnalyzerRun's); `succeeded` gains `data.preview`, a compact object built in code from the result for `translation`, `topic_extraction`, `propaganda_detection`, `techniques`, `llm_techniques`, `news_search`, `fact_check` and `source_info` (null for other analyzers).
- `analysis.finalizing` gains `data.activity` (key `finalizer`) and `data.progress`; `analysis.finalized` and `analysis.finalization_failed` gain `data.progress`.
- `scrape.started` gains `data.activity` (key `scrape`, detail naming the URL's host).
- `job.snapshot` gains `data.plan`, `data.progress`, `data.previews` and `data.activities`, so a late or reconnecting subscriber can rebuild the progress view without replay.
- Every change is additive: no existing member, event type, ordering guarantee or REST response changes. `GET /api/v1/jobs/{id}` and the Job object are unchanged.

The issue names `analysis-jobs-api` as the spec to document this; the event stream is specified in the `analysis-job-events` capability, so the delta lives there. `analysis-jobs-api` and the result capabilities are referenced, not modified.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `analysis-job-events`: `analysis.planned`, Activity, Progress, previews on settle events, progress on finalization events, scrape activity, snapshot replay members.

## Impact

- backend: engine (plan, progress, activities, previews, event members), snapshot in the WebSocket handler, registry `ui` block (`hidden`, `activity_key`), activity text table, preview builders; offline tests with stub adapters. One task.
- frontend: no change required. At d590b92, `frontend/src` has no WebSocket or `/events` consumer; consuming the new members is a follow-up feature.
- project: no change. The `full-e2e` suite is a placeholder; no new integration suite.
