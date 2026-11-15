# Design: chat focus

## Contract summary
```json
POST /api/v1/jobs/j1/chat
{
  "messages": [{"role": "user", "content": "Why were these flagged?"}],
  "language": "en",
  "focus": [
    {"kind": "technique", "ref": "Loaded_Language", "label": "Loaded language"},
    {"kind": "passage", "ref": "12:40:Loaded_Language", "label": "“a disaster for everyone”"}
  ]
}
```
Response: unchanged ChatReply.

### Kinds and references
| kind | ref | resolves to |
|---|---|---|
| `final_assessment` | `final_assessment` | `Job.finalization.result` (FinalAssessment), when finalization completed |
| `technique` | Detection `name` | the Detection in the `techniques` run `result.detected` with that `name` |
| `passage` | `<start>:<end>:<technique>` (decimal integers) | the TechniqueSpan of that Detection with equal `start` and `end` |
| `llm_finding` | 0-based decimal index | `llm_techniques` run `result.findings[index]` |
| `risk_dimension` | `intensity`, `confirmation` or `amplification` | `Job.risk.dimensions.<ref>` |
| `risk_driver` | 0-based decimal index | `Job.risk.drivers[index]` |
| `risk_caveat` | RiskCaveat `id` | the first `Job.risk.caveats` item with that `id` |
| `wikipedia_claim` | 0-based decimal index | `wikipedia` run `result.claims[index]` (ClaimLookup) |
| `term_context` | 0-based decimal index | `term_context` run `result.terms[index]` (TermContext) |

`passage` puts the technique name last so names may contain `:`. Spans of one Detection never share `start` and `end`
(technique-classifier-result "Span ordering and overlap"), so the reference is unique. Indexes are stable because a
completed job's result does not change (analysis-chat-api "Chat does not change the job").

Decision: unknown kinds and unresolvable refs are accepted (label-only, unresolved) instead of rejected, so the
client and server can add kinds independently and a stale client never breaks the chat. Only the shape is validated.

Decision: `focus` is per request, not per ChatMessage. The issue requires the selection to be sent with each
question; earlier turns keep their focus in the client (shown in the thread) but the server only needs the focus of
the new question. Adding focus to ChatMessage would change an object that is echoed back and is not needed.

Limits: 20 items; `kind` 1–40 code points; `ref` 1–200; `label` 1–500, non-blank after trimming. Worst case adds
about 15 KiB, well under the 1 MiB body cap of api-conventions.

## Change classification (rule: grep of every use)
`grep -rn "ChatRequest\|/chat" openspec/specs` finds uses only in `openspec/specs/analysis-chat-api/spec.md`.

| Change | Evidence | Class |
|---|---|---|
| New optional member `focus` on ChatRequest | analysis-chat-api/spec.md:15-16 ("Unknown members SHALL be ignored") | shared-additive |
| New 422 field keys `focus…` | analysis-chat-api/spec.md:22-23 (validation list); new condition only | shared-additive |
| Focus data passed as untrusted data | analysis-chat-api/spec.md:102-103 (Untrusted chat inputs), extended | shared-additive |
| Focused answers | analysis-chat-api/spec.md:91-92 (grounding), unchanged; new requirement adds an instruction | shared-additive |
| ChatReply, errors, limits, timeouts, eligibility | analysis-chat-api/spec.md:51-151 | unchanged |

No breaking change; no client migration needed.

## Rewritten clauses
"ChatRequest object" is rewritten to tolerant style ("at least"); no "exactly" clause is touched.
