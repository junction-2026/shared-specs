# Design: LLM finalizer verdict and user-facing text

## Context

Canonical contract (shared-specs @ 8d3a6d7):
`openspec/specs/analysis-jobs-api/spec.md:122-155` (FinalAssessment, overall score,
categories, evidence/limitations, insufficient-evidence short-circuit) and
`openspec/specs/analyzer-service-protocol/spec.md:64-87` (result conventions,
finalizer response, finalizer response validation). Backend @ 554a945 implements
it in `internal/finalizer/finalizer.go` with an `http_sync` entry in
`docs/examples/final_synthesis.yaml`. Nothing is deployed: on the live system the
finalizer is not configured and every job ends `finalization: skipped /
not_configured`.

## Goals / Non-goals

- Goal: a FinalAssessment that is the LLM's verdict, confidence and user text, so
  that a frontend can show a verdict and explanation without interpreting scores.
- Goal: keep every other part of the Finalization lifecycle (statuses, reasons,
  error codes, events, ordering, barrier, cancellation) unchanged.
- Non-goal: frontend changes (no client reads the result yet).
- Non-goal: putting the LLM provider protocol in shared specs (rule 13: the
  provider is not a repository of this project; no other repository depends on
  the request the backend sends it).

## Decisions

### D1. FinalAssessment shape

`verdict` (`detected` | `not_detected` | `uncertain`), `confidence` (number 0–1 or
null), `user_text` (non-empty string), `produced_by` (`finalizer` | `orchestrator`),
`usage` (object or null). "At least these members" applies: clients ignore unknown
members.

- `confidence` is optional in the finalizer output; the orchestrator stores an
  absent one as `null`. The backend's strict JSON schema may declare it required
  but nullable, which OpenAI strict mode needs; validation still accepts it absent.
- `usage` is the token usage the adapter reports (for the `llm` adapter the
  provider's `usage` object, verbatim) or `null`. It's on the result, as the parent
  issue asks, and is set only by the orchestrator, never taken from the LLM's JSON.
- Members of the finalizer output other than `verdict`, `confidence` and
  `user_text` are **dropped**, not kept verbatim as before. In `json_object` and
  `none` modes models often add members such as `reasoning`; storing them would
  pass unvalidated model text to clients, and rejecting them would fail too many
  answers that are otherwise valid.
- `user_text` length: the prompt asks for at most 120 words. Validation requires
  only a non-empty string. Words can't be counted reliably across languages, so
  enforcing the limit would fail usable answers. Clients must lay out longer text.
- `user_text` is model output influenced by untrusted content: clients render it as
  plain text (no HTML or Markdown interpretation, no links made from it).

Rejected: keeping `overall_score`/`categories` as optional members. The LLM output
has no such data, and two vocabularies of verdict would confuse clients.

### D2. Verdict vocabulary

`detected`/`not_detected`/`uncertain`, exactly as in the parent issue. Clients
SHALL treat an unknown future verdict value like `uncertain` (tolerant reader).
JobSummary `finalization.verdict` takes these values with no text change
(`analysis-jobs-api/spec.md:165` already says "the FinalAssessment verdict").

### D3. Insufficient-evidence short-circuit

It stays and is generalised: the orchestrator does not call the finalizer when no
AnalyzerRun that the finalizer would receive succeeded (for the `llm` adapter, the
analyzers opted in to LLM input; for `http_*` adapters, every AnalyzerRun). It then
completes with `verdict: uncertain`, `confidence: null`, a fixed non-empty
`user_text`, `produced_by: orchestrator`, `usage: null`. Calling the LLM with
every input unavailable would only produce `uncertain` at a cost, with a risk of an
invented verdict. The requirement keeps its name, so the reference in
`analysis-job-events/spec.md:80` ("insufficient-evidence short-circuit") stays
valid.

### D4. Status naming

The parent issue's acceptance criterion 1 says `finalization.status: succeeded`.
The canonical status for a finalization with a result is `completed`
(`analysis-jobs-api/spec.md:98`) and does not change. Criterion 1 is met by
`completed`.

### D5. Credentials in errors

`error.message` of a failed finalization may carry the provider's error message
(parent issue §5). The contract adds that it never contains credentials (API key,
`Authorization` value); the backend redacts the configured key from the text.

## Compatibility classification

Every place in the canonical specs that uses a changed object or rule
(grep of `verdict|overall_score|categories|explanation|evidence|limitations|EvidenceRef|Limitation|FinalCategory|insufficient`):

| Location | Change | Class |
|---|---|---|
| `analysis-jobs-api/spec.md:122-127` FinalAssessment object | members `overall_score`, `categories`, `explanation`, `evidence`, `limitations` removed; verdict values replaced; `confidence`, `user_text`, `usage` added; unknown finalizer members dropped instead of kept | **shared-breaking** |
| `analysis-jobs-api/spec.md:129-134` Overall score semantics | removed, replaced by Confidence semantics | **shared-breaking** |
| `analysis-jobs-api/spec.md:136-141` Assessment categories (FinalCategory) | removed | **shared-breaking** |
| `analysis-jobs-api/spec.md:143-148` Evidence references and limitations | removed | **shared-breaking** |
| `analysis-jobs-api/spec.md:150-155` Insufficient evidence short-circuit | new result shape; condition widened to "no AnalyzerRun the finalizer would receive succeeded" | **shared-breaking** |
| `analysis-jobs-api/spec.md:104-113` Finalization outcomes | codes unchanged; adds "message never contains credentials" | shared-additive |
| `analysis-jobs-api/spec.md:164-165` List jobs, JobSummary `finalization.verdict` | text unchanged; value set follows D2 | **shared-breaking** (values) |
| `analysis-jobs-api/spec.md:197-203` Registry listing hides execution settings | rule unchanged; new scenario for `api_key`/`base_url`/`model` | shared-additive |
| `analyzer-service-protocol/spec.md:64-69` Analyzer result conventions | EvidenceRef citation sentence and scenario removed; `result.evidence` SHOULD unchanged | **shared-breaking** (finalizer citations only) |
| `analyzer-service-protocol/spec.md:71-76` Finalizer response | new output shape for every adapter | **shared-breaking** |
| `analyzer-service-protocol/spec.md:78-87` Finalizer response validation | new validation rules | **shared-breaking** |
| `analyzer-service-protocol/spec.md:29-34` Job-wide binding sources | unchanged; still valid for `http_*` finalizers | none |
| `analysis-job-events/spec.md:54-84` Finalization events/ordering | unchanged; carry the Finalization object with the new result | none (follows the object) |

### Affected clients and migration

- **frontend** @ 3e51ec4: no use of `finalization.result` or JobSummary
  `finalization.verdict` (grep of `verdict|finaliz` in `src/` is empty). No
  migration; a future UI reads `verdict`, `confidence`, `user_text`.
- **backend** @ 554a945: `internal/finalizer` normalization/validation and the
  short-circuit move to the new shape; `docs/examples/final_synthesis.yaml` moves to
  `adapter: llm`. Done by the backend child of this feature.
- **External `http_sync`/`http_async` finalizer services**: none deployed. A future
  one returns `{verdict, confidence?, user_text}`.
- **project** integration harness @ 441ecbf: `full-e2e` is a placeholder and does
  not touch finalization.

## Risks

- A model may ignore the schema in `json_object`/`none` mode → validation fails
  with `invalid_output` and no verdict is shown (the intended safe failure).
- Prompt injection through content → content only inside `<content>`, the system
  prompt says it is data; output is still validated, and clients render
  `user_text` as plain text.

## Requirement map

- analysis-jobs-api: MODIFIED "Finalization outcomes" (text unchanged; credential
  rule moved to ADDED "Finalization errors hide credentials"), "FinalAssessment
  object", "Insufficient evidence without fabricated score", "Registry listing
  hides execution settings"; ADDED "Verdict values", "Confidence semantics", "User
  text rendering", "Finalization errors hide credentials"; REMOVED "Overall score
  semantics", "Assessment categories", "Evidence references and limitations".
- analyzer-service-protocol: MODIFIED "Analyzer result conventions", "Finalizer
  response", "Finalizer response validation"; ADDED "Finalizer output
  normalization".
