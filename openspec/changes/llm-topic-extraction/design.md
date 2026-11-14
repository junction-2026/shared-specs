# Design: LLM topic and news extraction analyzer

## Context

Canonical shared specs (shared-specs @ 7885bff) treat an analyzer's `result` as an
opaque JSON object (`openspec/specs/analysis-jobs-api/spec.md:65` "AnalyzerRun
object", `openspec/specs/analyzer-service-protocol/spec.md:64-69` "Analyzer result
conventions"). The backend (@ 20183d6) has an OpenAI-compatible `llm` adapter used
only by the finalizer. The frontend (@ 3e51ec4) reads no job objects.

## Goals / Non-goals

Goals: a stable, validated result shape for extracted topics and news that the
backend can produce and any client can read; the analyzer behaves like every other
analyzer in the job lifecycle. Non-goals: searching or fact-checking the topics,
changing the finalizer, frontend display.

## Decisions

1. **New capability instead of modifying `analysis-jobs-api`.** The AnalyzerRun
   object already carries any object in `result`; this capability defines what that
   object is for the analyzer with id `topic_extraction`. Keeping it separate leaves
   the canonical job API untouched and avoids overlapping
   `social-media-scrape-input`, which modifies `analysis-jobs-api` requirements.
2. **Clients find the result by analyzer id `topic_extraction`.** A deployment
   without that analyzer simply has no such AnalyzerRun; clients treat absence,
   `skipped` and `failed` as "no extraction available".
3. **The orchestrator builds the result.** The model's reply is decoded,
   validated against a fixed built-in schema and normalized (unknown members
   dropped, absent optional members as null, `usage` from the provider's report,
   same as FinalAssessment `usage`). Because the schema is built in, operators cannot
   change the shared shape through registry configuration.
4. **Empty lists are a success.** Text with nothing checkable or no news yields
   `topics: []` / `news: []`, not an error.
5. **No maximum list length or string length in the contract.** The backend prompt
   asks for at most 10 topics and 10 news items, but clients SHALL NOT rely on a
   maximum; a hard limit would turn a verbose model reply into a failure.
6. **Model output is untrusted.** Like `user_text` (`analysis-jobs-api/spec.md:204`), all strings are model output
   influenced by possibly adversarial input; clients render them as plain text.
   `query` is a search phrase, not a URL.
7. **Errors reuse existing codes** (`adapter_error`, `invalid_output`, `timeout`,
   `cancelled`) from "AnalyzerRun outcomes" (`analysis-jobs-api/spec.md:72-78`); no
   new code is introduced.

## Compatibility classification

| Use | Evidence | Change | Class |
|---|---|---|---|
| AnalyzerRun `result` | `analysis-jobs-api/spec.md:65-70` (any JSON object when `succeeded`) | defines the object for `topic_extraction` | shared-additive (new capability; existing members unchanged) |
| `analyzer.succeeded` event `data.analyzer.result` | `analysis-job-events/spec.md:34` ("Analyzer events") | carries the same object | shared-additive |
| `Job.analyzers` / `GET /api/v1/analyzers` | `analysis-jobs-api/spec.md:58` ("Job analyzer list"), `:172` ("List analyzers") | one more registry analyzer listed when configured | shared-additive (registry data, no schema change) |
| AnalyzerRun error codes | `analysis-jobs-api/spec.md:72-78` | reuses `invalid_output`, `adapter_error`, `timeout`, `cancelled` | no change |
| Analyzer selection | `analysis-jobs-api/spec.md:29-43` | `topic_extraction` is selectable like any regular analyzer | no change |
| Finalizer input / FinalAssessment | `analysis-jobs-api/spec.md:122-145`, `analyzer-service-protocol/spec.md:71-106` | analyzer may be opted into LLM input by backend configuration; FinalAssessment shape unchanged | no change |
| Registry listing hides execution settings | `analysis-jobs-api/spec.md:179-190` | base_url/api_key/model/headers of the new analyzer are covered by the existing rule | no change |

No shared-breaking change; no client migration is needed. No existing "exactly"
clause is touched. The one strict rule is that result strings must not be rendered as
markup (security, see decision 6).

## Overlap with active changes

`social-media-scrape-input` (project#8) modifies `analysis-jobs-api` and
`analysis-job-events`. This change modifies neither. For scrape jobs the analyzer
runs once the scraped Input is available, through the same rules as every other
analyzer; nothing here depends on that change.

## Risks

- Prompt injection in the input text: mitigated by passing the text as delimited data,
  strict schema validation and plain-text rendering (backend-local requirements).
- Provider support for `json_schema` varies: `response_format` stays configurable
  (`json_schema` | `json_object` | `none`); validation is always applied.
