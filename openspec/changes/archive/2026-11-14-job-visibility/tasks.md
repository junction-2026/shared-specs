# Tasks

## 1. Shared contract
- [x] 1.1 Delta spec for `analysis-jobs-api`: `public` in create body and Job, listing excludes non-public jobs.
- [x] 1.2 Compatibility classification in design.md.

## 2. backend (child `backend-job-visibility`)
- [ ] 2.1 Parse and validate `public` in `POST /api/v1/jobs` (default `true`; non-boolean incl. `null` -> 422 `validation_failed`, `details.fields.public`).
- [ ] 2.2 Add `public` to the Job; old stored JSON without the member decodes as `true`.
- [ ] 2.3 SQLite migration adding a `public` column (existing rows `1`) and index; filter before `LIMIT` in `Page`; same filter in the in-memory store.
- [ ] 2.4 Tests: create/validation, Job member, listing with status filter and cursor pagination, get/cancel/events of unlisted jobs, migration of an existing database.

## 3. frontend (child `frontend-job-visibility`)
- [ ] 3.1 `CreateJobBody`/`Job` types gain optional `public`.
- [ ] 3.2 Public switch (default on) in the Home composer with explanatory text in every locale; sends `"public": false` only when off.
- [ ] 3.3 Tests for the switch, request body and translations.
