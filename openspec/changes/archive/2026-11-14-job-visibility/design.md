# Design: job visibility

## Decisions
1. **Top-level boolean `public`** in the create body and on the Job (as suggested in the parent issue), not
   `options.public`: `options` holds analysis behaviour (`finalize`), visibility is a property of the job record.
   A boolean (not an enum such as `visibility: "unlisted"`) is enough for the stated non-goals (no ACL, no owners).
2. **Default `true`**, so every existing client and stored job keeps today's behaviour.
3. **Strict type check**: only JSON `true`/`false` are accepted; `null`, strings and numbers are 422
   `validation_failed` with `details.fields.public`. This follows "Create job validation" ("wrong member types").
4. **Filtering happens before paging**: `limit` and `next_cursor` count only public jobs, so a page is never
   shortened by hidden jobs and a cursor always names a public job. Cursors stay opaque; cursors issued before this
   change stay valid (they encode `created_at` and `id` only).
5. **Fixed at creation.** Changing visibility later is a non-goal (follow-up). No list parameter to include unlisted
   jobs is added: anyone could use it, which would defeat "not listed".
6. **JobSummary does not gain `public`**: every listed item would be `true`. Clients that need it read the Job.

## Compatibility classification (every place the touched endpoints and objects are used)

| Spec location (canonical, shared-specs @ 5981c9f) | Change | Class |
|---|---|---|
| `openspec/specs/analysis-jobs-api/spec.md:15` Create job | new optional request member `public` | shared-additive |
| `openspec/specs/analysis-jobs-api/spec.md:22` Create job validation | 422 for invalid `public` (new condition, existing code) | shared-additive |
| `openspec/specs/analysis-jobs-api/spec.md:233` Scrape request validation | unchanged; `public` is checked alongside it | none |
| `openspec/specs/analysis-jobs-api/spec.md:44` Job object | new member `public` (boolean, always present) | shared-additive |
| `openspec/specs/analysis-jobs-api/spec.md:152` Get job | returns unlisted jobs like any other | none |
| `openspec/specs/analysis-jobs-api/spec.md:159` List jobs | omits jobs with `public: false` | shared-additive (only jobs created with the new member are affected; existing clients never create them) |
| `openspec/specs/analysis-jobs-api/spec.md:166` Cancel job | unchanged for unlisted jobs | none |
| `openspec/specs/analysis-jobs-api/spec.md:498` Persisted jobs in listing and cancel | listing includes persisted public jobs only | shared-additive |
| `openspec/specs/analysis-jobs-api/spec.md:509` History retention | unchanged; retention removes unlisted jobs like others | none |
| `openspec/specs/analysis-job-events/spec.md:23,48,353,364` `data.job` in `job.snapshot` and terminal events | carries the new Job member `public`; events still equal the REST Job | shared-additive (no spec change) |
| `openspec/specs/api-conventions/spec.md:40` Cursor pagination | unchanged; applies to the filtered list | none |

No member is removed or renamed, no type or status of an existing case changes: there is **no shared-breaking change**
and no client migration is required. Tolerant readers (api-conventions) ignore `public` until they use it.

## Clients
- frontend (`src/api/types.ts` `CreateJobBody`, `Job`): add optional `public?: boolean`; History relies on the
  server filter and needs no change.
- No other client of `GET /api/v1/jobs` exists in the registered repositories.

## Risks
- A user may mistake "non-public" for private. The frontend copy must state that anyone with the link can open the
  job; the spec states that no access control is implied.
- Jobs are reachable by id; ids are not guessable sequences in the backend (opaque ids), but this change does not
  promise unguessability.

## Concurrent changes
- `term-context` (#49) also deltas `analysis-jobs-api`, but only the requirement "Wikipedia quotes for clients";
  no requirement header is shared with this change, so archive order does not matter.
- `wikipedia-cross-language` (#47) touches `wikipedia-lookup-result` only. Its frontend child edits
  `src/api/types.ts` and the locale files too; the members and keys added here are disjoint from its own.
