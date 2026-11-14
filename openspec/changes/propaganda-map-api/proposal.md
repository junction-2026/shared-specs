# Propaganda map: countries linked to detected propaganda across analyses (junction-2026/project#59)

Based on backend @ d03c1cc4ce1f941ef37a4b715c2de081ac65f379, frontend @ 8df0521d82acc7d94d6a90dd1751b1320f81b85f,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 5981c9fdec37dc8664689f5ff2595ae797da618a.

## Why
Explore's world map only shows the outlet countries of one job's news coverage (`/explore?job=<id>`). Users want
to see where propaganda shows up across **all** analyses: each finished analysis with detected propaganda
techniques is placed in the country of the analyzed page's outlet, and the map is shaded by how many such analyses
each country has, with a per-country list of those analyses.

## What changes
- New shared capability `propaganda-map-api` (additive only; no existing requirement is modified):
  - A **map analysis** is a done job that `GET /api/v1/jobs` lists, whose `techniques` AnalyzerRun `succeeded`
    with a non-empty `detected`, and whose **map country** is known.
  - The **map country** comes from the analyzed page's outlet: the `source_info` result's `page_outlet` when that
    run succeeded, otherwise the deployment's outlet table matched against `input.source.url` with the existing
    Outlet matching rules. It is never inferred from language, text or a TLD.
  - `GET /api/v1/map/countries`: per-country aggregates (`country_code`, `country`, `analyses`, technique counts)
    plus the total `analyses`; not paginated.
  - `GET /api/v1/map/countries/{country_code}/analyses`: the map analyses of one country, newest first, with the
    api-conventions cursor pagination; each item has job id, timestamps, source URL/title, a plain-text snippet,
    the page outlet, detected techniques (with strength when stored) and the final verdict.
  - Jobs stored before this change are included (derived from their stored results); values are fixed once a job
    is done; retention-removed jobs disappear.
- Not shared (common rule 13): storage of the derived country/techniques, the schema migration and backfill, the
  query strategy (backend local change); the map shading scale, tooltip, panel, keyboard/touch access, copy and
  coexistence with `/explore?job=<id>` (frontend local change).

## Impact
- Shared capability added: `propaganda-map-api`. `analysis-jobs-api`, `source-info-result`,
  `technique-classifier-result` and `api-conventions` are read, not modified (see design.md for the evidence).
- backend: store columns/table with migration and backfill, two read endpoints, tests.
- frontend: `/explore` without `job` becomes the global propaganda map; `/explore?job=<id>` is unchanged.
- Overlapping work (planned around, not modified; `base_changes` is empty):
  - `job-visibility` (junction-2026/project#53, plan branch, not on main) adds unlisted jobs. This change defines
    map analyses as jobs that `GET /api/v1/jobs` lists, so unlisted jobs never appear on the map whichever change
    lands first, and no requirement of `job-visibility` is touched.
  - `wikipedia-cross-language` (#47, active), `term-context` (#49) and `analysis-chat-api` (#57) touch other
    requirements/capabilities; no textual or semantic overlap.
