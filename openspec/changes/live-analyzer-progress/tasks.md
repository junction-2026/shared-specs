## 1. Shared contract

- [ ] 1.1 Review and approve the `analysis-job-events` delta (plan, activity, progress, previews, snapshot members)
- [ ] 1.2 Publish the change on shared-specs `main` (no archive until the feature integrates)

## 2. Backend (child `backend-live-analyzer-progress`)

- [ ] 2.1 Registry `ui` block (`hidden`, `activity_key`), `text_stats` hidden by default
- [ ] 2.2 Plan computation and `analysis.planned` emission; Progress tracking on the job record
- [ ] 2.3 Activity table, details and params; `activity` on `analyzer.started`, `analysis.finalizing`, `scrape.started`
- [ ] 2.4 Preview builders for the eight analyzers; `preview`, `progress`, `availability`, `note` on settle events; `progress` on finalization events
- [ ] 2.5 `job.snapshot` members `plan`, `progress`, `previews`, `activities`
- [ ] 2.6 Offline tests with stub adapters for every acceptance criterion; README event docs; local OpenSpec change; `go test ./...`

## 3. Frontend and project

- [ ] 3.1 No change in this feature: frontend @ d590b92 has no event-stream consumer; project `full-e2e` is a placeholder
