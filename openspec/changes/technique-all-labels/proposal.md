# Proposal: technique-all-labels

Parent: junction-2026/project#16 (extends junction-2026/project#15; rebased onto #17 `technique-spans`).

Based on: backend @ 08109f8725584ea93d2274c90a226aa3eeb8997b (`internal/adapter/technique.go`,
`technique_spans.go`, `technique_names.go`, `internal/registry/technique.go`,
`docs/examples/technique_classifier.yaml`), frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a
(`src/job/JobView.tsx`, `src/job/api.ts`: reads `detected[].name/display/explanation/spans` and
`span_status`), project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e` placeholder only),
shared-specs @ cc519ddf5f3975258c6f3d0a09c47867bcdd8dc0 (canonical `technique-classifier-result`
including the archived #17 span requirements).

## Why

#15 shipped a `techniques` analyzer that picks one model (`short`/`long` by word count) and reports
a `detected` list with per-technique thresholds plus per-sentence detections on the translation;
#17 added `detected[].spans` in the user's original text, which the frontend job view now
highlights. #16 asks for every technique label with its score from the NCI document model
(`nci-technique`) and/or the NCI short-post model (`nci-social`, max 128 tokens), each with the
model, its cutoff and an `above_cutoff` flag; both result sets kept when both run (no averaging);
unfamiliar labels kept. Where #16 conflicts with #15 (short/long, `thresholds` map, per-sentence
detections and offsets) #16 wins. The result reaches clients verbatim through
`Job.analyzers[].result` and `analyzer.succeeded` (`analysis-jobs-api/spec.md:74`,
`analysis-job-events/spec.md:34`), so its shape is an interface between repositories.

## What Changes

- **technique-classifier-result** (modified; see design.md for the per-element classification):
  - New `results`: one ModelResult `{model, cutoff, scores, latency_ms}` per model that ran
    (`nci-technique` before `nci-social`); each TechniqueScore
    `{label, display, score, model, cutoff, above_cutoff, known}`. All 18 known labels per model,
    below-cutoff scores included, unfamiliar labels kept with `known: false`.
  - Routing by word count of `translated_text`: < 40 words → `nci-social`; 40–80 → both;
    > 80 → `nci-technique` (bounds configurable). Never averaged or merged.
  - One cutoff per model (defaults 0.5 / 0.3, configurable, echoed); per-technique overrides gone.
  - **`detected` and its `spans` are kept** (the frontend reads them): a known technique is
    detected when it is `above_cutoff` in at least one ModelResult; Detection gains `models`
    and loses its own `score` (no merged score). All #17 span rules stay as they are.
  - Classification requests carry only the English `translated_text`.
  - **Removed** (no client reads them): top-level `model`, `threshold`, `thresholds`,
    `techniques`, `max_score`, `latency_ms`, `sentences`, `offsets_in`, `sentences_truncated`;
    Detection `score`; SentenceDetection.
- Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
  `api-conventions`, `propaganda_detection`, the span step and its members
  (`span_method`, `span_status`, `spans_truncated`, TechniqueSpan).

## Decisions for approval

- **Keep `detected` + spans instead of replacing the object.** The previous draft of this plan
  removed `detected`; since then #17 shipped and frontend @ 1abe19a highlights `detected[].spans`.
  Keeping `detected` (now derived from `above_cutoff`) means no frontend change, matching the
  issue's "no new frontend work".
- **Routing rule** (left to the planner by the issue): no BERTweet tokenizer in the backend, so the
  128-token limit is checked with a conservative word bound (80 words × ~1.5 tokens + 2 specials
  ≤ 128); "long enough to be a document" is ≥ 40 words. Both bounds are backend config.
- **Detection without score**: a merged or "best" score would contradict "never merged into one
  score"; clients read per-model scores from `results`. `models` says which model(s) flagged it.
- **Unfamiliar labels** stay in `results` only; `detected` holds known names (they have an
  explanation and are what spans and the frontend key on).
- **All-or-nothing**: when both models are needed and either fails, the run fails.
- **Per-sentence detections on the translation and `offsets_in` dropped**; highlighting in the
  user's text is provided by #17's spans.
- **One backend task**; no frontend or project task.

## Overlapping work

- junction-2026/project#18 (`source-info-result`, deployed and archived): same backend
  registry/adapter packages, other files; no contract overlap.
- junction-2026/project#17 (`technique-spans`, deployed and archived into canonical): this change
  keeps all of its requirements; it rewrites the five that mention removed members (see design.md).

## Impact

- backend: `technique_classifier` adapter (routing, one or two model calls, ModelResult output,
  unknown labels, `detected` from `above_cutoff`, sentence batches removed), registry keys,
  example YAML with the new `llm.description`, README, tests. The span step is unchanged except
  that it receives the new `detected`.
- frontend, project: no change.
