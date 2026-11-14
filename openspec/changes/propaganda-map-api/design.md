# Design: propaganda-map-api (junction-2026/project#59)

Based on backend @ e8c46a1e6e4ab169e6376c5da627d0c71ae0b2ba, frontend @ 4339d356d14fb7a76474428da2756afcd0c184b1,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 5f4e9e4789a043c2ee8620f54fc3da58cea1cb86
(main with `term-context` #49 and `analysis-chat-api` #57 active, and `job-visibility` #53, `wikipedia-cross-language` #47 and
`russian-localization-language` #60 archived).

## Decisions

### D1. Country = the analyzed page's outlet, with an outlet-table fallback
The parent issue fixes the country to `source_info.page_outlet.country_code`. In the current backend `source_info`
depends on `news_search` (source-info-result.md:8), so when `news_search` is skipped (e.g. `no_searchable_topics`) or
fails, `page_outlet` is never computed although the job has a URL. Rule (2) of "Map country" applies the **same**
offline Outlet matching (source-info-result.md:70) to `input.source.url` with the deployment's outlet table, so
those jobs are placed too. It is the same verified lookup, not inference from TLD/language (non-goal kept). When
`source_info` succeeded its stored `page_outlet` wins, so the map agrees with the job's own result.

### D2. "Propaganda detected" = non-empty `techniques.detected`
Per the issue, detection by the classifier's existing cutoffs (technique-classifier-result.md:241). Weak detections
count (the issue says "by its existing cutoffs"); `strength` is passed through per technique (MapTechnique) so the
UI can show weak hints as weaker (technique-classifier-result.md:346, :394). `llm_techniques`,
`propaganda_detection` and the verdict do not decide membership, keeping the definition single-sourced.

### D3. Scope = public jobs, i.e. jobs `GET /api/v1/jobs` lists
`job-visibility` (#53) is now canonical: a Job has `public` (analysis-jobs-api.md:57, :601) and the listing leaves
out `public: false` jobs (analysis-jobs-api.md:171, :612). Map analyses are restricted to `public: true` jobs, so the
map never becomes a way to discover unlisted jobs; jobs stored before `public` existed count as public
(analysis-jobs-api.md:602), so they are included. Retention (analysis-jobs-api.md:525) removes jobs from the map.

### D4. Values fixed at `done`; old jobs included
Deriving once when a job is done (and once for stored jobs on upgrade) keeps aggregates stable and cheap to query
(backend stores them; storage and migration are backend-local). Old jobs are backfilled from stored results rather
than ignored, so the map is useful immediately after deploy.

### D5. Two endpoints under `/api/v1/map`
- `GET /api/v1/map/countries`: not paginated (at most ~250 ISO codes), ordered by code; total `analyses` for the
  legend/empty state. The client computes the scale maximum itself.
- `GET /api/v1/map/countries/{country_code}/analyses`: api-conventions cursor pagination (api-conventions.md:40),
  newest first like the jobs listing. Unknown-but-well-formed codes return an empty page (not 404) so a click on any
  country needs no special casing; malformed codes are 400 `invalid_request` (api-conventions.md:29).
- Items carry a bounded `snippet` instead of the full `input.content` (which can be up to 1 MiB) and link by `job_id`.

## Compatibility classification (common rule 13 / step 2)

Every object and endpoint this change touches or reuses, grepped in canonical specs on main @ 5f4e9e4 (`openspec/specs/` is byte-identical to 5bd4073 and e646135 for
analysis-jobs-api, source-info-result, technique-classifier-result and api-conventions, so the line numbers hold):

| Item | Where used today | Change | Class |
|---|---|---|---|
| `GET /api/v1/map/countries` | nowhere (`grep -rn "/api/v1/map" openspec/specs` → none) | new endpoint | shared-additive |
| `GET /api/v1/map/countries/{country_code}/analyses` | nowhere | new endpoint | shared-additive |
| CountryAggregate, TechniqueCount, MapAnalysis, MapTechnique | new objects | new | shared-additive |
| Outlet object (source-info-result.md:89) | SourceInfo `articles[].outlet`, `page_outlet` (source-info-result.md:103) | reused read-only inside MapAnalysis `outlet`; unchanged | none |
| Detection `name`/`display`/`strength` (technique-classifier-result.md:256, :346) | `techniques` result | values copied; unchanged | none |
| FinalAssessment `verdict` (analysis-jobs-api.md:142, :210) | Job, JobSummary | value copied; unchanged | none |
| Job object incl. `public`, List jobs, Job visibility (analysis-jobs-api.md:56, :171, :601) | jobs API, events | referenced for scope (`public: true` only); unchanged | none |
| Error codes `invalid_request`, `method_not_allowed` (api-conventions.md:29) | all endpoints | reused on a new endpoint | shared-additive |

No existing member, status or error is removed, renamed or re-typed: **no shared-breaking change, no client
migration**. Existing clients that never call `/api/v1/map/*` are unaffected. All new objects are "at least" objects
(api-conventions.md:52); no "exactly" clause is introduced.

## Overlap with term-context (#49, active)
`term-context` modifies analysis-jobs-api "Wikipedia quotes for clients" (openspec/changes/term-context/specs/
analysis-jobs-api/spec.md:3) and adds `term-context-result`. propaganda-map-api modifies no analysis-jobs-api
requirement and ignores the `term_context` AnalyzerRun (Detected propaganda reads only `techniques`; Map country
reads only `source_info` and `input.source.url`). The new `term_context` run in `analyzers[]` does not change a
job's `done` state semantics, so the "Map values fixed when done" derivation is unaffected. No contradiction in
either archive order.

## Overlap with analysis-chat-api (#57, active, IMPLEMENTING)
`analysis-chat-api` (active change on shared-specs main @ 5f4e9e4, `openspec/changes/analysis-chat-api/`) adds only
`POST /api/v1/jobs/{id}/chat`; this change adds only `GET /api/v1/map/*`. The paths, objects and error conditions are
disjoint, neither modifies a canonical requirement, and chat never changes a job (so it never changes map values).
No shared contradiction in either merge or archive order; nothing here builds on it, so `base_changes` stays empty.
Local overlap (approver allowed parallel work) is kept to append-only edits in different requirements and files:
- backend `orchestrator-http-server`: this feature adds one `route(basePath+"/map/...")` pair in
  `internal/httpapi/httpapi.go` (next to the existing `route` calls, httpapi.go:80-88) and puts its handlers in a new
  `internal/httpapi/map.go`; #57 adds its chat route and its own handler file. Only ADDED requirements in the local
  delta; no existing orchestrator-http-server requirement is modified.
- frontend `backend-api-client`: this feature appends `getMapCountries` and `listCountryAnalyses` at the end of
  `src/api/client.ts` and puts its tolerant types in a new `src/api/mapTypes.ts` (not `types.ts`); one ADDED
  requirement "Propaganda map client"; existing requirements are not modified.
- frontend `secondary-screens`: not modified by this feature. The global map lives in the `explore-coverage`
  capability (`src/explore/`, `src/views/ExploreView.tsx`); the Explore country panel keeps its "Inspect wire feeds →"
  link, so "Explore and Region screens" / "Explore and Region navigation" still hold. #57 changes only the Ask screen.
- frontend i18n: strings only in the `explore` namespace (`src/i18n/locales/<lang>/explore.ts`); #57 uses `ask`, #49
  uses results/term namespaces; the i18n runtime is not touched.

## Non-shared (local) parts
- backend: persisted map columns/table, migration + backfill, Memory-store derivation, query/index strategy, tests.
- frontend: global map mode on `/explore`, shading scale, legend, tooltip, panel, keyboard/touch, i18n in all six
  UI locales (`en`, `fr`, `ar`, `de`, `fi`, `ru`, in the `explore` namespace), tests;
  `/explore?job=<id>` unchanged.

## Risks
- Many analyses are pasted text without a URL → no country; the UI empty state explains that only analyses of pages
  from known outlets appear.
- Outlet-table coverage limits placement (unmatched domains are not placed). Intended (no inference).
- Weak-only analyses are counted; the panel shows strength so users can judge.
