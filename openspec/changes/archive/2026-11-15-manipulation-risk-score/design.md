# Design: Manipulation Risk Score (junction-2026/project#64)

Based on backend @ c1d660fc, frontend @ 108bbf79, project @ 441ecbf9, shared-specs @ 197c3a52.

## Mapping the four models to existing analyzers
| Issue model | Analyzer / member | Evidence |
|---|---|---|
| 1 Propaganda Technique Classifier | `techniques` ModelResult `nci-technique` | technique-classifier-result spec.md:41-58, 184-212 |
| 3 Social Media Propaganda Classifier | `techniques` ModelResult `nci-social` (texts up to 80 words) | technique-classifier-result spec.md:41 |
| 2 Binary Propaganda Detector | `propaganda_detection` result `result[] {label, score}` | backend internal/adapter/propaganda.go `checkPropaganda`; analysis-job-events spec.md:264-266 (preview) |
| 4 Bot / AI-Generated Content Detector | `bot_detection` analyzer | backend docs/examples/bot_detection.yaml (disabled by default, response shape undocumented) |

No model is added. Because the bot detector's response shape is not a shared contract (and the issue forbids changing
raw outputs), the backend maps it with deployment configuration (member paths for author score, author post count,
single-text score). Until a deployment enables and maps it, amplification is reported unavailable with
`analyzer_unavailable` / `no_bot_score` and the UI explains why.

## Decisions
1. **Job-level member, not an analyzer.** An analyzer with `depends_on` would be `skipped` whenever an input analyzer
   fails (analysis-jobs-api spec.md:99-108), which contradicts graceful degradation. The orchestrator computes the
   score itself at the settle barrier (`analysis.ready_for_finalization`, analysis-job-events spec.md:54-60, 68-78),
   before finalization, so a finalizer failure never affects it.
2. **No new event.** "Finalization and completion ordering" (analysis-job-events spec.md:79-84) requires
   `job.completed` to directly follow `analysis.ready_for_finalization` when finalization is skipped; a new event would
   break that. The score rides on `analysis.ready_for_finalization` as `data.risk` and on the Job.
3. **Model choice for intensity.** The issue says model 3 replaces model 1 for short posts. "Short" uses the same
   80-word bound as the classifier routing, as a separate config value (`short_text_max_words`). Exactly one
   ModelResult is read, honouring "Separate model results" (technique-classifier-result spec.md:220-225).
4. **Detection threshold `> 0.3`** on the chosen model, independent of the per-model `cutoff` (0.5 / 0.3), as the
   issue specifies; the risk technique list is therefore its own list (`risk.techniques`), not `detected`.
5. **Intensity scaling.** `density = min(1, N/6)`, `weighted_intensity = min(1, Σ p·w / 5.0)`, intensity = mean.
   Six high-impact techniques at 0.8 give 0.98, so plausible maxima stay below 1. Linear clipping keeps hand
   reconstruction trivial.
6. **Confirmation probability.** The detector returns a label with its confidence; the propaganda probability is the
   `PROPAGANDA` score, else `1 − NO_PROPAGANDA` score.
7. **Dampening.** Confirmation `< 0.2` multiplies the combined score by `dampening_factor` 0.6 (issue: "overall score
   is dampened"); `raw_score` keeps the undampened value for reconstruction.
8. **Missing dimensions.** Amplification missing → the issue's explicit 0.55/0.45 weights. Intensity or confirmation
   missing → available base weights renormalised. Neither content dimension → `unavailable` (a score from the bot
   signal alone would describe the author, not the content).
9. **Author context** = succeeded scrape or non-empty `input.source.author`; history ≥ 20 posts → author basis,
   otherwise single-text score with `confidence: low`.
10. **Config echoed** in every RiskScore so a stored score stays reconstructible after recalibration.
11. **Texts.** English template texts from the server plus stable keys (`band`, driver `kind`/`technique`, caveat `id`)
    so the localized frontend (frontend src/i18n, six locales) can use its own catalog.

## Contract change classification
| Change | Where used (canonical) | Class |
|---|---|---|
| New member `Job.risk` | Job object analysis-jobs-api spec.md:56-57; returned by create/get (spec.md:15, 164), `data.job` of `job.snapshot` / terminal events (analysis-job-events spec.md:22-23, 47-48); persisted verbatim (analysis-jobs-api spec.md:503-504) | shared-additive (new optional member; api-conventions spec.md:55 tolerant reader) |
| New member `data.risk` on `analysis.ready_for_finalization` | analysis-job-events spec.md:54-55 | shared-additive |
| New capability `manipulation-risk-score` (RiskScore and sub-objects) | new | shared-additive |
| JobSummary (`GET /api/v1/jobs`), AnalyzerRun results, previews, FinalAssessment | unchanged | none |

No breaking change; no client migration. Clients that predate this change ignore `risk`. Jobs stored before it have
no `risk` (treated as null). "Snapshot members are not Job members" (analysis-job-events spec.md:363-368) is respected:
`risk` is a real Job member, so REST and `data.job` stay equal.

## Overlap
Active change `propaganda-map-api` (#59) adds a separate capability and endpoints; no shared requirement overlaps.
