# Design: technique-spans

## Contract surface and classification

Canonical references are shared-specs @ 518903a.

| Element | Used at | Change | Classification |
|---|---|---|---|
| TechniqueClassification members `span_method`, `span_status`, `spans_truncated` (new requirement "Span result members"; "TechniqueClassification object" text unchanged) | `technique-classifier-result/spec.md:27` (object, "at least", "Clients SHALL ignore unknown members"); delivered verbatim via `analysis-jobs-api/spec.md:74` (`result` verbatim) and `analysis-job-events/spec.md:34` (`analyzer.succeeded` with `result`) | new members | shared-additive |
| Detection member `spans` (only Detections in `detected`) | `technique-classifier-result/spec.md:48` (Detection "at least") | new member | shared-additive |
| Detection inside `sentences[].techniques` | `technique-classifier-result/spec.md:59` | unchanged; does not carry `spans` | unchanged |
| `sentences`, `offsets_in`, `sentences_truncated` | `technique-classifier-result/spec.md:58-74` | unchanged | unchanged |
| AnalyzerRun `status`/`error.code` of `techniques` | `technique-classifier-result/spec.md:76-85` | span-step failure does NOT add a failure case; the run still succeeds | unchanged (new condition is reported inside `result`, not as a run failure) |
| Presentation rule | `technique-classifier-result/spec.md:94-99` | adds span text and highlighting rules, and forbids presenting translated sentences as the user's words | shared-additive (new client obligation; no client reads this result yet: frontend @ 3e51ec4 has only the health page) |

`grep -rn "technique\|offsets_in\|Detection" openspec/specs` finds the Detection object only in
`technique-classifier-result`; no other capability reuses it. No member is removed,
renamed or changes type or meaning, so no client migration is required.

The "Detected techniques" requirement used no "exactly" clause; the rewritten text keeps
the tolerant "at least" style. The 18-name list ("SHALL be these 18 strings") is not touched.

### Backward compatibility

Results stored before the backend change have no `spans`, `span_method`, `span_status`
or `spans_truncated`. Clients SHALL treat a missing `spans` member as "no span analysis"
(show the technique without highlight), which the presentation requirement states.

## Span production (contract-level)

- **Language decision**: `source_language` of the `translation` result. `"en"` →
  `span_method: "sentence"`; any other value or missing → `"phrase"`.
- **sentence**: the original `Job.input.content` (not the translation, not
  `normalized_content`) is split into sentences; up to the deployment's sentence limit
  are scored by the sentence model; for each Detection in `detected`, every scored
  sentence whose sentence-model score for that technique is at or above the sentence
  model's effective threshold for it becomes a span. Sentence scores of techniques not
  in `detected` are ignored.
- **phrase**: one LLM request with the original content and the names of the detected
  techniques. Each candidate is accepted only if it is non-empty and occurs in
  `Job.input.content` as an exact, case-sensitive substring of UTF-16 code units. Its
  span is the leftmost occurrence. Duplicate accepted candidates of one technique give
  one span. Candidates for techniques not in `detected` are ignored. Nothing is
  trimmed, normalized, translated or repaired.
- **No call** is made when `detected` is empty (`span_status: "ok"`).
- **Ordering**: spans of one technique by `start` ascending, then `end` ascending.
  Spans of different techniques may overlap and the same range may appear under
  several techniques.

## Failure isolation

The span step has its own deadline inside the analyzer's timeout. A non-2xx answer,
connection error, unreadable response or elapsed span deadline sets `span_status` to
`failed` (or `timeout` for the deadline) and every `detected[].spans` to `[]`. The run
still `succeeded`; document scores, `detected`, `sentences` and `offsets_in` are the
same as without spans. If the analyzer's overall timeout elapses, the existing `timeout`
failure of the whole run applies (unchanged).

## Backend-local (not in this change)

Registry configuration of the sentence model (`nci-social` endpoint, headers, threshold,
overrides) and the LLM (base_url, api_key, model, prompt, response schema), span
deadline, caps, the original-text sentence splitter, prompt design, retries and docs
are requirements of the backend task's local change.

## Frontend-local (not in this change)

Job result view, highlight rendering, colours, legend and accessibility are
requirements of the frontend task's local change.

## Risks

- LLM near-matches are rejected by design; some techniques will show `spans: []`.
- Extra latency/cost: one sentence-model batch (English) or one LLM call (other
  languages) per job with detections.
- The sentence model and the document model may disagree, so an English detection can
  have no sentence span; this is reported as `spans: []`, not hidden.
