## Context

Based on backend @ dfe8c12b98ebd33cbd038c8863e9086f09718618. `adapter.LLM` (`internal/adapter/llm.go:60`) is the only path to the provider, for the finalizer (`internal/finalizer/finalizer.go:90`), `topic_extraction` (`internal/adapter/topic.go:90`) and technique spans (`internal/adapter/technique_spans.go:167`). Today it retries once on a connection error, 429 or 5xx (`llmSend`). Every reply problem goes to `decodeReply` and becomes `invalid_output`.

## Goals / Non-Goals

Goals: make the retry visible to clients through `attempts` and `retry_reason`, define what `usage` means across two requests, and keep the existing failure semantics.

Non-goals: the retry prompt text, the registry settings, the time budget and the fallback model. These are runtime behaviour of the backend and go in the backend's local OpenSpec change. Also out of scope: more than one reply retry, and any change to the 429/5xx retry, the prompts or the word limit.

## Decisions

1. **Members on the result objects, not on AnalyzerRun or Finalization.** `attempts` and `retry_reason` describe one LLM call, and the result object already carries that call's `usage`. Putting them there leaves the AnalyzerRun object, which every analyzer shares, unchanged.
2. **`attempts` is null when no LLM call was made.** That covers `produced_by: orchestrator` and the `http_sync`/`http_async` finalizers. Clients can then tell "no LLM" apart from "one LLM request". Results stored before this change have no such members, and clients treat an absent member as null.
3. **`retry_reason` values are an "includes" list**: `length`, `invalid_json`, `schema`. `invalid_json` covers empty content and content that is not a JSON object after removing a code fence. `schema` covers a JSON object that fails the configured output schema or the built-in checks. For the finalizer these are the conditions of "Finalizer response validation". For `topic_extraction` they are the conditions of "Topic extraction output validation".
4. **Usage summing.** Each numeric member is summed. Nested objects (such as `prompt_tokens_details`) are summed the same way, recursively. A member present in only one report keeps that value. Non-numeric members take the retry's value. When neither attempt reported usage, `usage` is null. This keeps the "provider token usage object" shape, including a provider `cost` member.
5. **Failure after retry stays `invalid_output`.** `error.message` is free text and is not a contract. The backend puts both reasons in it.

## Change classification (evidence from shared-specs @ 04e47a1)

Every place in the canonical specs that defines or uses the changed objects:

| Object / requirement | Spec evidence | Change | Class |
|---|---|---|---|
| FinalAssessment object | `openspec/specs/analysis-jobs-api/spec.md:130-139` ("at least") | add `attempts`, `retry_reason`; `usage` summed | shared-additive (new optional members). The `usage` meaning is extended only for the new two-request case; single-request results are unchanged |
| Insufficient evidence assessment | `analysis-jobs-api/spec.md:141-150` (object listed literally) | listing rewritten to "at least", new members null | shared-additive |
| Finalizer output normalization | `analyzer-service-protocol/spec.md:97-106` ("set `usage` to the token usage reported by the adapter … drop every other member") | not modified: the adapter reports the summed usage, and `attempts`/`retry_reason` are set by the orchestrator, not taken from the output. The new FinalAssessment requirement states this | none |
| Finalizer response validation | `analyzer-service-protocol/spec.md:78-95` | unchanged. These conditions now trigger one retry for `llm` before `invalid_output` | none (failure contract unchanged) |
| Finalization outcomes / errors | `analysis-jobs-api/spec.md:112-121` (`invalid_output` code) | unchanged | none |
| TopicExtraction object | `topic-extraction-result/spec.md:19-24` ("at least", "Clients SHALL ignore unknown members") | add `attempts`, `retry_reason`; `usage` summed | shared-additive |
| Topic extraction output normalization | `topic-extraction-result/spec.md:73-78` (scenario "the stored result is {…}" is exact) | scenario rewritten to "at least" with the new members; `usage` rule references summing | shared-additive |
| Topic extraction failures | `topic-extraction-result/spec.md:80-85` | unchanged (429/5xx retry untouched) | none |
| `analysis.finalized` / `analyzer.succeeded` events | `analysis-job-events` embed the same objects by reference | no separate change; the events carry the new members | shared-additive |
| news-search-result | `news-search-result/spec.md:27` quotes a topic_extraction result in a WHEN clause | input example only. Readers ignore unknown members | none |

No shared-breaking change. Affected clients: frontend (reads neither object member at 1abe19a; no migration needed).

## Overlap with active changes

`remove-closed-platform-scraping` (feature #24) was archived into the canonical specs at shared-specs @ 04e47a1 after this plan branch was cut. It changed `analysis-jobs-api` only in "Scrape failure causes" (scenario now uses `mastodon`, new scenario "Unsupported social network URL"). This change's delta was re-checked against the merged canonical text: the MODIFIED requirements "FinalAssessment object" and "Insufficient evidence without fabricated score" are unchanged on main and keep their full canonical wording, and this change does not touch "Scrape failure causes", so archiving it keeps feature #24's requirements. No other active change touches `analysis-jobs-api` or `topic-extraction-result`.

## Risks / Trade-offs

- Summed `usage` can't be split back into the two requests. That is acceptable: `attempts` says two requests were made, and per-attempt detail goes in the backend logs.
- A retry costs extra latency and tokens. The backend bounds it with a time budget and one retry at most.
