# Proposal: Ask VEIL chat about a finished analysis

## Why
junction-2026/project#57. The `/ask` screen ("Ask VEIL") is a frontend mock with canned answers and no backend
(frontend `docs/mock-areas.md`, capability `secondary-screens` "Ask screen"). Users want to ask follow-up questions
about the result of a finished analysis. A self-hosted OpenAI-compatible agent runs next to the backend; the backend
calls it, grounds it in the job's analysis result and presents it as **VEIL**. The frontend needs a stable endpoint to
build the real chat on, so the endpoint is a shared contract.

## What Changes
- **New capability `analysis-chat-api`**: `POST /api/v1/jobs/{id}/chat`, non-streaming.
  - Request `{"messages": [ChatMessage], "language": <optional UI language>}`; the client sends the conversation
    (stateless server, no stored chat history). ChatMessage `{"role": "user" | "assistant", "content"}`; the last
    message is the user's new question. Limits: 1–40 messages, user content ≤ 2000 and assistant content ≤ 8000
    code points; the server uses at most the latest 20 messages and says so with `history_truncated`.
  - Response 200 ChatReply, at least `{"job_id", "message": {"role": "assistant", "content"}, "history_truncated",
    "created_at"}`; `content` is plain text of at most 8000 code points (so it can be sent back as history).
    ChatReply deliberately never carries the upstream agent, model, provider, URL, usage or credentials.
  - Errors (includes): 404 `not_found`; 409 `job_not_completed` (`details.status`) for any job whose `status` is not
    `completed`; 400 `invalid_request`; 422 `validation_failed`; 413 `payload_too_large`; 429 `rate_limited`
    (`Retry-After` header and `details.retry_after_s`); 503 `chat_unavailable`; 504 `chat_timeout`.
  - The assistant presents itself as VEIL, answers about that job's analysis only, and treats analysed content and
    client-sent history as data, never as instructions. Chat never changes the job and emits no event.

All changes are additive: one new endpoint and new error codes on new conditions. No existing object, status or error
code changes. No auth (the API has none, per `api-conventions`).

## Non-goals
Streaming (SSE) replies; server-side or cross-device chat history; chat before or without a completed analysis;
changing the agent container or its configuration; UI layout, persona prompt wording, upstream configuration and
deployment networking (component-local requirements, see `design.md`).

## Based on
backend @ b10abc3560797c99b31df3ace32440e5ce4118a4, frontend @ d2a04eaa1d88589507bf9692a2896bbe108cfdd4,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 1c82dde3ba58cad81b5e0907f0f999d7af01b376.
