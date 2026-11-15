## 1. Shared contract
- [ ] 1.1 Approve MODIFIED analysis-jobs-api "List jobs" and the ADDED requirements "Job list language filter", "Job list language paging", "Job list language scope", "JobSummary language", "JobSummary language for clients"
- [ ] 1.2 At archive time re-check "List jobs" against canonical main: only the `language` filter and member are new

## 2. backend (child `backend-history-language`)
- [ ] 2.1 Derived job language stored at write time (memory and SQLite), indexed
- [ ] 2.2 Appended SQLite migration adding the column/index, with backfill of existing rows in batches
- [ ] 2.3 `language` query parsing and validation, filter applied before paging with `q`, `status` and public-only
- [ ] 2.4 JobSummary `language`; tests (handler, stores, migration of a populated old database)

## 3. frontend (child `frontend-history-language`)
- [ ] 3.1 `listJobs` `language` parameter; `JobSummary.language?: string | null`
- [ ] 3.2 History language filter control (fixed list plus unknown), URL state, paging reset, export with the filter
- [ ] 3.3 Item language label; locale strings in all UI locales; tests
