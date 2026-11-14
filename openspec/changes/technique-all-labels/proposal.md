# Proposal: technique-all-labels

Parent: junction-2026/project#16 (extends the deployed junction-2026/project#15).

Based on: backend @ 7331be7d92235bac756d572ad684a413eb178e0d (`internal/adapter/technique.go`,
`technique_split.go`, `technique_names.go`, `internal/registry/technique.go`, `adapter.go:107`
`job_content` input, `docs/examples/technique_classifier.yaml`), frontend @
3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (no job or analyzer client), project @
441ecbf96961128099af004da50a063f18b3345c (`full-e2e` placeholder only), shared-specs @
c999ac2e9f1e1a386c62d8cfbc13adff9a58f546 (canonical `technique-classifier-result`, archived from #15).

## Why

#15 shipped a `techniques` analyzer that picks one model (`short`/`long` by word count), reports
a `detected` list with per-technique thresholds and per-sentence detections with offsets. #16
asks for something different: every technique label with its score from the NCI document model
(`nci-technique`) and/or the NCI short-post model (`nci-social`, max 128 tokens), each with the
model, its cutoff and an `above_cutoff` flag; both result sets kept when both run (no averaging);
unfamiliar labels kept. Where #16 conflicts with #15 (short/long, `thresholds` map, per-sentence
detections and offsets) #16 wins. The result reaches clients verbatim through
`Job.analyzers[].result` and `analyzer.succeeded` (`analysis-jobs-api/spec.md:74`), so its shape
is an interface between repositories. The earlier plan for #16 edited #15's unarchived change;
#15 has since been archived, so this is a new change that modifies the canonical spec.

## What Changes

- **technique-classifier-result** (modified, **shared-breaking** for the result object; see design.md):
  - TechniqueClassification becomes `{words, results: [ModelResult], ...}`; ModelResult is
    `{model, cutoff, scores, latency_ms}`; TechniqueScore is
    `{label, display, score, model, cutoff, above_cutoff, known}`.
  - `model` values `nci-technique` / `nci-social` (was `short` / `long`); routing by word count
    with both models for the middle band; both kept separately, never averaged.
  - All 18 known labels per ModelResult, below-cutoff scores included; unfamiliar labels kept
    with `known: false` (were `invalid_output`).
  - One cutoff per model (defaults 0.5 / 0.3, configurable, echoed); per-technique overrides gone.
  - Only the English `translated_text` is sent to the models.
  - **Removed**: `threshold`, `thresholds`, `techniques`, `detected`, `max_score`, `sentences`,
    `offsets_in`, `sentences_truncated`, top-level `model`/`latency_ms`, Detection and
    SentenceDetection objects.
- Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
  `api-conventions`, `propaganda_detection`.

## Decisions for approval

- **Breaking replacement instead of side-by-side members.** Keeping #15's `detected`/`sentences`
  next to `results` would need the old single-model routing and sentence batches alongside the new
  routing, and two contradictory "detected" notions. No client reads the result (frontend @ 3e51ec4
  has no job client), so the shape is replaced. Results of jobs run before the backend change keep
  the old shape (stored verbatim); clients treat a `techniques` result without a `results` array as
  "no technique analysis available".
- **Routing rule (the issue leaves it to the planner).** The backend has no BERTweet tokenizer, so
  the 128-token limit is checked with a conservative word bound: `nci-social` runs when
  `words <= social_max_words` (default 80: 80 words × ~1.5 tokens + 2 special tokens ≤ 128);
  `nci-technique` runs when `words >= technique_min_words` (default 40, "long enough to be a
  document") or `words > social_max_words`. So < 40 words → social only; 40–80 → both; > 80 →
  technique only. Both bounds are backend config; `words` and each `cutoff` are echoed.
- **Score order**: the 18 known labels in the spec's fixed order, then unknown labels in the
  model's order. Clients sort for display.
- **All-or-nothing**: when both models are needed and either fails, the run fails (no partial result).
- **Per-sentence detections and offsets dropped** (left to the planner by the issue). They can
  return as an additive member later (see the conflict note on #17 below).
- **One backend task**, no frontend or project task (issue non-goals; no integration suite runs ML
  models; `full-e2e` is a placeholder).

## Overlapping work

- junction-2026/project#18 (`source-info-result`, deployed and archived): touches the same backend
  registry/adapter packages but other files; no contract overlap.
- junction-2026/project#17 (`technique-spans`, plan branch `plan/17-technique-spans-highlight-exact`
  @ b89838e, not merged): its delta adds `spans` to Detection in `detected` and keeps `sentences`,
  which this change removes. If #17 is still active it must be re-planned on top of this change
  (e.g. spans per above-cutoff TechniqueScore); the two deltas must not both be approved as written.

## Impact

- backend: `technique_classifier` adapter (routing, two-model calls, result shape, unknown labels),
  registry keys (`technique`/`social` blocks with `cutoff`, `social_max_words`,
  `technique_min_words`; `short`/`long`/`threshold(s)`/`max_sentences` removed), no `job_content`
  input, example YAML with the new `llm.description`, README, tests.
- frontend, project: no change.
