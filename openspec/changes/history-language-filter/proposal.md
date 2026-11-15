## Why

junction-2026/project#80: the History list (`GET /api/v1/jobs`) can be filtered by `status` and searched with `q`, but not by the language of the analysed text. A job has no language member of its own; the only language the system knows is the `source_language` of the job's succeeded `translation` AnalyzerRun, already normalized by analyzer-service-protocol "Source language binding source".

## What Changes

- `analysis-jobs-api` "List jobs" (MODIFIED): names the optional `language` filter and the JobSummary `language` member.
- New requirements in `analysis-jobs-api`:
  - "Job list language filter": optional query parameter `language` (two-letter ISO 639-1 code, or `unknown`), case-insensitive after trimming; any other non-empty value yields 400 `invalid_request`.
  - "Job list language paging": `language` combines with `q`, `status` and the public-only rule (all must hold), is applied before paging, and clients following `next_cursor` send the same parameters.
  - "Job list language scope": covers the whole persisted history, including jobs stored before this change.
  - "JobSummary language": additive optional member `language` (lower-case code or null), the same value the filter matches.
  - "JobSummary language for clients": a missing member reads as null; clients show the code via their own names.
- Additive only: no existing member, status or error case changes (see design.md).

## Capabilities

### New Capabilities
- none

### Modified Capabilities
- `analysis-jobs-api`: job list `language` filter and JobSummary `language`.

## Impact

- backend: derived, indexed job language stored at job write time in the memory and SQLite stores; appended SQLite migration with backfill of existing rows; `language` query parsing and JobSummary serialization.
- frontend: API client `language` parameter and `JobSummary.language`; History language filter control kept in the URL with the other filters.
- No new endpoint; the UI offers a fixed list of common languages plus `unknown`.

Based on backend @ 881c056588bf5b1057bd05c58925c4a375928f0c, frontend @ c0db797fa2558441374a77b1a90bae1a2b4ec72b, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ d654f43a7c0d3546b6a31caa764705f461c3c590.
