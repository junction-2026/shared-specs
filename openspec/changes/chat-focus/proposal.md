# Focus the Ask VEIL chat on selected result elements (junction-2026/project#93)

Based on shared-specs @ bd681f5668c056b0cfa7b45a5e413233aec386bc, backend @ 88b185a5190ac72542782e734446a2c1d31b22bf,
frontend @ 6c7f45bc57dfc2b5506c0ea371de30263629fbc6, project @ 441ecbf96961128099af004da50a063f18b3345c.

## Why
The Ask VEIL chat (`POST /api/v1/jobs/{id}/chat`) only sees a job as a whole. Users want to point VEIL at specific
parts of the result (a detected technique, a highlighted passage, a risk driver, a Wikipedia claim, ...) and ask
about those. The client therefore needs a way to tell the server which result elements a question is about.

## What changes
- `analysis-chat-api` (shared-additive): ChatRequest gains an optional `focus` member, an array of at most 20
  ChatFocusItem objects `{kind, ref, label}`. `kind` names the type of result element, `ref` identifies it within
  the job (a reference grammar per kind is defined, e.g. a Detection `name`, a span `<start>:<end>:<technique>`, a
  0-based index), `label` is the short plain text the user saw.
- Validation: 422 `validation_failed` with `error.details.fields` keys `focus`, `focus[<i>]`, `focus[<i>].kind`,
  `focus[<i>].ref`, `focus[<i>].label` for malformed focus (not an array, more than 20 items, non-object items,
  missing/blank/too long strings). Absent, `null` or `[]` means no focus and keeps today's behaviour.
- Resolution: the server resolves each item against the job's own result; items it cannot resolve (unknown kind,
  unknown ref) do not fail the request and are given to the assistant by label only, marked unresolved. Labels are
  untrusted data, never instructions; resolved result data takes precedence over the label.
- The assistant is instructed to answer the new question about the focused elements, using the rest of the analysis
  only as context. No analysis is re-run; ChatReply is unchanged; the upstream stays hidden.
- `focus` applies to the request's new question only. The server keeps no conversation; ChatMessage is unchanged.

## Not shared (common rule 13)
- Frontend (`ask-chat`, `backend-api-client`): split-pane layout, selectable result elements, selection chips,
  per-turn focus markers in the thread, session storage of per-turn focus, i18n in en/de/fr/fi/ar/ru, RTL.
- Backend (`analysis-chat`): parsing, prompt layout of the focus data, size caps of the focus message, logging.

## Compatibility
- Old clients send no `focus` and get exactly the current behaviour.
- A new client against a backend without this change: ChatRequest already ignores unknown members, so the request
  succeeds and the answer is unfocused (degrades gracefully, no error).
- No existing member, status code or error code changes meaning.

## Impact
- Shared capability: `analysis-chat-api` only.
- Repositories: backend (validate, resolve, prompt), frontend (Ask VEIL split pane). No project test-harness change:
  the `full-e2e` suite is still a placeholder.
