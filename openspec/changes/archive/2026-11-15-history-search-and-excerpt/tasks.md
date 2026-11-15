# Tasks: history-search-and-excerpt

## 1. Shared contract
- [x] 1.1 Delta spec `analysis-jobs-api`: List jobs (modified), Job list search, Job list search scope and paging, JobSummary excerpt
- [x] 1.2 Compatibility classification in design.md

## 2. Backend (junction-2026/backend)
- [ ] 2.1 Parse and validate `q` in `GET /api/v1/jobs` (trim, 200-char limit, 400 `invalid_request`)
- [ ] 2.2 Filter by `q` before paging in the memory and SQLite stores, combined with `status` and public-only
- [ ] 2.3 Add `excerpt` to JobSummary
- [ ] 2.4 Tests for every scenario of the delta spec

## 3. Frontend (junction-2026/frontend)
- [ ] 3.1 `listJobs` accepts `q`; `JobSummary.excerpt` type; items use `excerpt` instead of per-job `getJob`
- [ ] 3.2 Functional search box, empty state for no matches
- [ ] 3.3 Export button downloads a CSV of the full history
- [ ] 3.4 Remove the History meta line and its i18n keys; update `docs/mock-areas.md` and local specs
- [ ] 3.5 Tests
