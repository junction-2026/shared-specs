## 1. Shared contract
- [ ] 1.1 Approve ADDED requirements in `analysis-jobs-api` and `analysis-job-events`

## 2. backend (child `backend-sqlite-job-store`)
- [ ] 2.1 Store persistence boundary and SQLite implementation (pure Go), config, auto-migration
- [ ] 2.2 Startup recovery marking interrupted jobs per "Jobs interrupted by a restart"
- [ ] 2.3 REST and event stream serve persisted jobs per "Job history persistence" / "Event stream of a persisted job"
- [ ] 2.4 Tests (round-trip of all analyzer result types, restart reload, interruption, concurrency, eviction) and README
