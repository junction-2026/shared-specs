# Propaganda map: countries linked to detected propaganda across analyses (junction-2026/project#59)

Based on backend @ 85cebc311e4b34337c064d0e5d85929dbbb206be, frontend @ 07d8c49ca54cb6e643d8bee82ba1c71c75c9e7b2,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ e64613598d5da0836396308a99c3a46889cea6d0
(main after `job-visibility` #53 and `wikipedia-cross-language` #47 were archived).

## Why
Explore's world map only shows the outlet countries of one job's news coverage (`/explore?job=<id>`). Users want
to see where propaganda shows up across **all** analyses: each finished analysis with detected propaganda
techniques is placed in the country of the analyzed page's outlet, and the map is shaded by how many such analyses
each country has, with a per-country list of those analyses.

## What changes
- New shared capability `propaganda-map-api` (additive only; no existing requirement is modified):
  - A **map analysis** is a done job with `public: true` (so `GET /api/v1/jobs` lists it), whose `techniques` AnalyzerRun `succeeded`
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
- Overlapping work: none active. `job-visibility` (#53) and `wikipedia-cross-language` (#47) are archived on main;
  this change reads the canonical `public` member (non-public jobs never appear on the map) and modifies no
  requirement of either. `base_changes` is empty.
