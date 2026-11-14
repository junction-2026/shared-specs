# Manipulation Risk Score in the analysis result (junction-2026/project#64)

Based on backend @ c1d660fc03f70ec8ae995a4e24dd8229c7e2265d, frontend @ 108bbf79cdf415c814f077dc112090257cde0a19,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 197c3a52651e6b726f45f3b46982e81fdaedb5d7
(main with `propaganda-map-api` #59 active; this change neither modifies nor builds on it).

## Why
The result screen shows each detection model's output separately. Readers need one transparent, educational
**Manipulation Risk Score** that combines the outputs the deployment already produces, and that never appears
without its band, its main drivers and its caveats. No model is added or retrained.

## What changes
- New shared capability `manipulation-risk-score` (ADDED requirements): the RiskScore object, how it is computed
  deterministically from the settled `techniques`, `propaganda_detection` and `bot_detection` AnalyzerRuns, the
  configuration it echoes, its drivers, caveats and degradation when inputs are missing.
  - The four models of the issue map onto existing analyzers: technique classifier = `techniques` ModelResult
    `nci-technique`; social-media classifier = `techniques` ModelResult `nci-social`; binary detector =
    `propaganda_detection`; bot / AI-content detector = the deployment's `bot_detection` analyzer (registry example
    exists, disabled by default). When an analyzer is absent, skipped or failed, its dimension is reported unavailable
    with a reason and the score is computed from the rest.
- `analysis-jobs-api` (ADDED "Job risk member"): new Job member `risk` (RiskScore or null). Additive.
- `analysis-job-events` (ADDED "Risk score with the settle barrier"): `analysis.ready_for_finalization` also carries `data.risk`.
  Additive; event order and types are unchanged.

## Out of scope (local to the owning repository)
- backend: configuration file and loading, bot-detector result mapping, computation code, persistence, tests.
- frontend: Risk Score section of the Results screen (headline, info tooltip, bars, technique list, drivers,
  caveats), localisation, accessibility, tests.

## Impact
- Clients that ignore unknown members (api-conventions) are unaffected. Existing AnalyzerRun results, previews and the
  FinalAssessment are unchanged.
- Children: `backend-risk-score` (backend), `frontend-risk-score` (frontend); independent, both build on this contract.
