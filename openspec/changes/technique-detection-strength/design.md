# Design: technique-detection-strength

Based on backend @ 10ac227cb99faad73a75dbcbcd12c20425f7d7ef, frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 18def034782c3f2db61a163a886af7863c9c34c4.

## Decisions

1. **Strength is computed by the producer, not by clients.** `margin`, `located` and `strength` are stored in
   each Detection so the finalizer, the UI and stored results agree, and a later change of `strong_margin` does
   not reinterpret old results. The setting itself is not exposed in the result.
2. **Margin rounding.** `margin` = max over the ModelResults named in `models` of (`score - cutoff`) for the
   Detection's `name`, rounded half away from zero to 2 decimals. `strength` compares the rounded `margin` with
   `strong_margin`, so a client re-deriving it from the stored numbers gets the same answer
   (0.65 - 0.5 = 0.15000000000000002 rounds to 0.15 and is `strong` at the default 0.15). Because `models` only
   lists models at or above cutoff, `margin >= 0`.
3. **Located follows the final spans.** `located` is evaluated after the span step. When `span_status` is
   `failed` or `timeout`, every `spans` is `[]`, so every Detection is `located: false` and its strength
   depends on `margin` alone. Both `span_method` values count.
4. **Summary.** `summary.strong + summary.weak` equals the length of `detected`; with `detected: []` it is
   `{strong: 0, weak: 0}`.
5. **Verdict meanings.** The shared Verdict values requirement currently says `uncertain` covers "weak"
   evidence, which is exactly the behaviour the parent removes. It is restated in terms of strong signals. The
   list of what counts as a strong signal (finalizer prompt) is backend-local; the API only states that weak
   hints alone lead to `not_detected`. The orchestrator's insufficient-evidence short-circuit (no analyzer
   evidence → `uncertain`) is kept and covered by "no evidence".

## Classification of affected uses (canonical specs @ 18def03)

| Changed item | Where it is used | Class |
|---|---|---|
| Detection gains `margin`, `located`, `strength` (new requirement Detection strength members) | `technique-classifier-result/spec.md:256-261` (Detection object), `:241-254` (Detected techniques by cutoff), `:92-97` (empty spans), `:99-100` (highlighting presentation) | shared-additive: new members; Detection is "at least" (:257) |
| Detection object sentence "A Detection carries no score of its own" | `technique-classifier-result/spec.md:257` | unchanged; the new Detection strength members requirement states `margin` is derived from `results`, not a score of its own |
| TechniqueClassification gains `summary` | `technique-classifier-result/spec.md:26-39`; returned in `analyzer.succeeded` and `GET /api/v1/jobs/{id}` (same requirement) | shared-additive: "at least" object, "Clients SHALL ignore unknown members" (:27) |
| Results without the members | `technique-classifier-result/spec.md:37-39`, `:88-90` (older stored results) | shared-additive: new compatibility scenario, missing members mean unknown strength |
| Verdict values meanings | `analysis-jobs-api/spec.md:198-203`; same values in `analyzer-service-protocol/spec.md:79` (validation, unchanged) | shared-additive in shape (same three values, same unknown-value fallback); meaning of `uncertain` narrowed and `not_detected` widened. No client code depends on the meaning: the frontend at d590b92 does not render `verdict` (no match for `uncertain`/`not_detected` in `src/` outside tests). |

No member is removed, renamed or retyped; no status changes. No shared-breaking change.

Other uses checked: `llm-technique-result` (separate analyzer, unchanged), `analysis-job-events` (carries the
result unchanged; active change `live-analyzer-progress` touches progress events only, no overlap),
`wikipedia-claim-lookup` (new capability, no overlap).

## Client migration

None required. Clients that want to show strength read `strength` when present and show no strength
indicator when it is missing (results stored before this change).
