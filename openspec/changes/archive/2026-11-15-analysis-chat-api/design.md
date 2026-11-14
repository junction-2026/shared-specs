# Design: Ask VEIL chat (analysis-chat-api)

## Context
Based on backend @ e8c46a1e6e4ab169e6376c5da627d0c71ae0b2ba, frontend @ 4339d356d14fb7a76474428da2756afcd0c184b1,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 5bd40738633bfa21b0e371a364003408af42e773.

Today:
- `/ask` is a mock (frontend `src/views/AskView.tsx:9`, `secondary-screens` "Ask screen", `docs/mock-areas.md` row
  `/ask`), reached from the Results view link `href="/ask"` (`src/views/ResultsView.tsx:101`,
  `results-history-views` spec line 218) without a job id.
- The backend has no chat route (`internal/httpapi/httpapi.go:80-88`); the closest pattern is the read-only job
  sub-resource `GET /jobs/{id}/localization` (shared `job-text-localization`), which also calls an LLM provider with a
  timeout and hides credentials.
- The frontend nginx proxies `/api/` with `proxy_read_timeout 5s` (`nginx/default.conf.template`, `frontend-runtime`
  "nginx behaviour"); a chat call needs a dedicated longer location.
- The API has no authentication and no CORS (same-origin proxy), `api-conventions/spec.md:22-38` (error envelope,
  common codes, 1 MiB body limit via 413).

## Decisions
1. **Sub-resource `POST /jobs/{id}/chat`, non-streaming.** Fits the existing job sub-resource pattern and the plain
   JSON client (`backend-api-client` "REST client"). The issue accepts non-streaming for v1; SSE would need a new
   client and proxy setup for little gain. Streaming can later be a new endpoint or an opt-in member.
2. **Stateless server, client-sent history.** No storage, no session ids, works for persisted jobs after a restart,
   nothing to expire or leak across users. Bounds: 1–40 messages, user ≤ 2000 / assistant ≤ 8000 code points
   (≈ 40 × 8000 ≈ 320k code points ≤ 1 MiB worst case with UTF-8, so the existing 413 limit stays the outer bound),
   server window = latest 20 messages starting at a `user` message, reported as `history_truncated`. Reply content is
   capped at 8000 code points so a reply can always be sent back as history.
   Clients can forge `assistant` turns; that only affects their own conversation, the persona and grounding are
   server-side and client turns are treated as data.
3. **`system` role rejected.** The persona prompt must not be overridable by clients (issue constraint).
4. **Eligibility = `status: completed`.** One code `job_not_completed` (409, `details.status`) covers
   queued/running/failed/cancelled, as the issue asks. `job_not_finished` of job-text-localization is not reused
   because a failed job is finished but still not eligible. Completed jobs with failed/skipped finalization are
   eligible: their analyzer results are still worth discussing.
5. **Language is a hint, never an error.** Unlike the localization endpoint (where the language is the resource), a
   chat answer can always fall back to the language of the question, so an unsupported `language` is not rejected.
6. **Limits.** Per-job rate (backend default 10 requests/minute), one in-flight request per job, and a global cap of
   concurrent upstream calls (backend default 4) → 429 `rate_limited` with `Retry-After`/`details.retry_after_s`
   (same detail name as `social-scraper-api` `rate_limited`). Keyed per job, not per client: behind the frontend
   nginx the backend sees the proxy's address, and the API has no client identity.
7. **Timeouts.** Upstream timeout default 90 s, response within 100 s; frontend nginx chat location
   `proxy_read_timeout 120s`; client waits ≥ 120 s. 504 `chat_timeout` vs 503 `chat_unavailable` lets the UI word the
   error; both are retryable.
8. **Upstream hidden.** ChatReply and errors never name the agent/model/provider/URL or carry usage/credentials
   (security exception to tolerant reader, stated in the spec, like `analysis-jobs-api` "Registry listing hides
   execution settings").
9. **Plain-text rendering** mirrors `analysis-jobs-api` "User text rendering" (`analysis-jobs-api/spec.md:224`).
10. **Languages follow job-text-localization.** The `language` hint is matched like "Localization languages"
    (`job-text-localization/spec.md:27-28`), which now includes `ru` (#60, archived on main); the frontend has an `ru`
    catalog (`src/i18n/locales/ru/`), so the chat UI copy covers en/de/fr/fi/ar/ru.

## Compatibility classification
| Change | Where used today | Class |
|---|---|---|
| New endpoint `POST /api/v1/jobs/{id}/chat` | none (grep `chat` in `openspec/specs`: no match) | shared-additive |
| New objects ChatRequest, ChatMessage, ChatReply | none | shared-additive |
| New error codes `job_not_completed`, `rate_limited` (on this endpoint), `chat_unavailable`, `chat_timeout` | new conditions only; `rate_limited` already exists as a scrape error code (`social-scraper-api/spec.md:175`) with the same meaning and `retry_after_s` detail | shared-additive |
| Job object, Job status, error envelope, common codes (`api-conventions/spec.md:22-38`, `analysis-jobs-api/spec.md:56-75`) | read only, unchanged | none |

No existing endpoint, object, status or error code changes; no client migration needed.

## Overlapping active work
- **#49 `term-context`** (active on shared-specs main @ 5bd4073, IMPLEMENTING; capabilities `term-context-result`,
  `analysis-jobs-api` one additive requirement). This change neither modifies nor depends on it; `base_changes` is
  empty. Its new `term_context` analyzer result is an ordinary analyzer result, so once it ships it is part of the
  grounding data by "Assistant identity and grounding" without any change here. `analysis-chat-api` is a new
  capability that only reads the Job object, so no shared capability is changed by both features.
- **Frontend `i18n` overlap with #49 `frontend-term-cards`** (approver allowed parallel work). Locale catalogs are
  split per namespace (`src/i18n/locales/<lang>/<namespace>.ts`). The chat task adds its strings only to the existing
  `ask` namespace (`src/i18n/locales/{en,de,fr,fi,ar,ru}/ask.ts`), does not touch `results.ts`, `analysis.ts`,
  `techniques.ts`, `common.ts` or the i18n runtime (`src/i18n/*.ts[x]`), and does not rename or remove any key
  outside `ask.*`. The only results-view edit is the `href` of the "Ask VEIL" link (`src/views/ResultsView.tsx:101`)
  and its test assertions, so the two tasks merge without textual or key conflicts. The chat UI does not reference
  term cards.

## Component-local decisions (not part of the shared contract)
- **backend**: upstream client (OpenAI-compatible `POST {base}/chat/completions`, model default `hermes-agent`), env
  `CHAT_BASE_URL` (default `http://127.0.0.1:8642/v1`), `CHAT_MODEL`, `CHAT_API_KEY` / `CHAT_API_KEY_FILE` (secret,
  never committed or logged), `CHAT_TIMEOUT`, limits; persona system prompt file; grounding builder with size caps;
  README deployment note on reaching a loopback-bound agent from a container (host networking, or bind the agent to
  the Docker bridge and use `host.docker.internal` with `host-gateway`).
- **frontend**: route `/jobs/:id/ask`, real thread/composer/states, session-scoped thread storage, nginx chat
  location, i18n, error copy, mock list.

## Risks
- The upstream is an *agent* that may have its own server-side tools. The backend sends no `tools`, but tool use
  configured inside the agent is outside this contract; prompt injection from analysed content could still try to
  trigger them. Mitigation here: content passed as delimited data plus the persona prompt; operators should run the
  agent with tools disabled for this use (out of scope per issue non-goals).
- Persona compliance is model behaviour; it is enforced by prompt and verified by a manual smoke, not by a
  deterministic filter.
- The API key was posted in Discord; it must be rotated and provided only as a deployment secret.
