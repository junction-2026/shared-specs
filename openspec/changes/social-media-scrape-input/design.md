# Design: Social-media scraping as job input

## Context

Canonical shared specs at shared-specs @ 729fe96 define text-only job input
(`openspec/specs/analysis-jobs-api/spec.md:8-17`). The handover proposes a separate
FastAPI scraper (`POST /scrape {url, max_posts}`, Bearer auth, `GET /health`). The
backend orchestrator (Go, backend @ fbf9e6f, which already contains the project#6
LLM finalizer) has no scraper client. The frontend
(@ 3e51ec4) does not call `/api/v1/jobs` at all (`grep -rn "api/v1\|jobs" src` is
empty), so no client reads the job objects yet.

## Goals / Non-goals

Goals: one contract that the scraper service, the orchestrator and later clients can
implement concurrently; typed errors for every failure; scraped profile, history and
comments available to the bot and propaganda analyzers. Non-goals: classifier
changes, private accounts, login-as-user, monitoring or bulk crawling, frontend URL
input (no submission form exists yet).

## Decisions

1. **Scraper is a separate service with its own shared API** (`social-scraper-api`).
   It lives in the backend repository under `scraper/` (Python FastAPI). It is shared
   because outside clients reach it through Traefik and because the orchestrator and
   the service are built by separate tasks against it.
2. **Flat ScrapeResult kept from the handover draft** (`platform`, `username`, …,
   `posts`, `latency_ms`) so the VPS draft stays close to compliant; additions are
   `url_kind`, `post`, `comments`, `warnings`, `profile_url`, `scraped_at`. Counters
   and `verified` are nullable because several platforms do not expose them; `0`
   would be a fabricated value.
3. **Asynchronous scrape phase inside the job.** `POST /api/v1/jobs` with `scrape`
   returns 201 at once (the existing "MUST NOT wait" rule extends to the scraper).
   The job is `scraping` until the scrape settles. Platform support is decided by the
   scraper only, so the orchestrator holds no platform list.
4. **Scrape failure ends the job `failed`.** The analysis never ran, so `completed`
   would mislead and the insufficient-evidence assessment is not produced. Analyzers
   and finalization are `skipped` with the new reason `input_unavailable`, keeping
   Coverage consistent and every AnalyzerRun settled.
5. **Mapping to Input.** `content` is the post text (post URL) or the history texts
   joined by blank lines (profile URL), so the propaganda analyzer works unchanged on
   `$input`; the full ScrapeResult rides in `source.metadata.scrape`, so the bot
   analyzer can bind `$input.source` (existing binding source,
   `analyzer-service-protocol/spec.md:22-23`) for profile, history and comments. The
   1 MiB request limit does not apply (the input is built server-side); `max_posts`
   ≤ 100 and `max_comments` ≤ 200 bound its size.
6. **Error pass-through.** Scraper error codes are passed into `scrape.error.code`
   with their `details`; orchestrator-side failures add `scraper_unavailable`,
   `timeout`, `cancelled` and `no_text_content`. A scraper 401 (wrong orchestrator
   token) is reported as `scraper_unavailable`, a configuration problem, not a user
   error.
7. **Parallel with project#6 (`llm-finalizer-verdict`), no contradicting delta.**
   That change modifies analysis-jobs-api "Finalization outcomes", "FinalAssessment
   object", "Insufficient evidence without fabricated score" and "Registry listing
   hides execution settings", adds "Verdict values", "Confidence semantics", "User
   text rendering", "Finalization errors hide credentials", removes "Overall score
   semantics", "Assessment categories", "Evidence references and limitations", and
   changes analyzer-service-protocol finalizer requirements. This change modifies or
   removes none of them and references no FinalAssessment member, so the two deltas
   archive independently in either order. Interactions, stated so both hold:
   - The finalization skip reason `input_unavailable` is added in the ADDED
     requirement "Scrape failure outcomes"; "Finalization outcomes" lists reasons as
     "including" (api-conventions tolerant enums), so no edit of it is needed.
   - After a failed scrape the finalizer is not called and no insufficient-evidence
     assessment (`verdict: uncertain`, `produced_by: orchestrator`) is produced:
     the job is `failed`, not `completed`. After a successful scrape every
     project#6 rule applies unchanged, including the insufficient-evidence
     short-circuit when no opted-in analyzer succeeded.
   - The backend-local `llm` adapter (backend `analysis-finalizer` "LLM prompt
     assembly") sends `normalized_content` only, so for scrape jobs the LLM sees the
     post text or joined history, never `source.metadata.scrape`; author signals
     reach it only through analyzer results of analyzers opted in with
     `llm.include` (backend-local registry config, not shared).
   - Scrape error messages follow the same no-credentials rule as project#6's
     "Finalization errors hide credentials" (stated in "Scrape failure causes").

## Compatibility classification

Every place that uses an object or endpoint this change touches (canonical
shared-specs @ 729fe96):

| Change | Used at | Class |
|---|---|---|
| `POST /api/v1/jobs` accepts `scrape` instead of `input` | analysis-jobs-api `spec.md:15-20`; api-conventions `spec.md:33,37,59` | shared-additive: new optional member; every existing body stays valid with the same result |
| New validation cases and 503 `scrape_unavailable` | analysis-jobs-api `spec.md:22-27`; api-conventions common codes `spec.md:29-38` | shared-additive: new code on a new condition; existing cases keep their status |
| Job gains `scrape` (null for text jobs) | Job object `spec.md:44-49`; Get job `spec.md:157-162`; `job.snapshot` events `spec.md:22-31`; terminal events `spec.md:47-52` | shared-additive: new member |
| `Job.input` is null while a scrape job is `scraping` or after its scrape failed | Job object `spec.md:44-49`; snapshot and terminal events (as above); `$input` binding `analyzer-service-protocol/spec.md:22-23` | **shared-breaking** (type of an existing member becomes nullable), limited to jobs created with the new `scrape` member; text jobs are unchanged. Affected clients: frontend — none today (no jobs client); backend analyzers never see it because no analyzer starts before the scrape succeeded. Migration: clients that render `input` treat null as "not yet available" and show `scrape.url` |
| New status `scraping`; `failed` also for failed scrapes | Job status `spec.md:51-56`; List jobs status filter `spec.md:164-169`; tolerant enums api-conventions `spec.md:61-63` | shared-additive: new value on a new case; clients handle unknown status via `done`; no existing case changes status |
| Skip reason `input_unavailable` (AnalyzerRun and Finalization) | AnalyzerRun outcomes `spec.md:72-77`; Finalization outcomes `spec.md:107-117`; Coverage `spec.md:93-98` | shared-additive: new value in "includes" lists |
| Events `scrape.started/succeeded/failed`; lifecycle restated | analysis-job-events `spec.md:15-20` (unknown types ignored), `40-52`, `68-77` | shared-additive: new event types; existing text-job ordering unchanged |
| New capability `social-scraper-api` | none (new) | shared-additive |

No existing "exactly" clause is touched. "Registry listing hides execution settings"
(the deliberate exception) is unchanged; the scraper URL and token are orchestrator
configuration, not analyzer listing members, and Scrape error messages must not
contain them.

## Risks

- Platform fragility (Threads SSR, Facebook GraphQL, Instagram datacenter-IP blocks,
  X cookie expiry) surfaces as `upstream_error`, `rate_limited` or
  `platform_not_configured`, never as 500; fixture-based tests cannot detect upstream
  drift.
- The release pipeline builds one image per repository from the root `Dockerfile`; the
  scraper image (`scraper/Dockerfile`) is built and published by an extra CI job, and
  its deployment (Traefik subdomain, `ml_net`, port 8003, secrets) remains operator
  work on the VPS.
- The bot-detector service (:8001) request shape is not documented in any repository;
  the example analyzer config sends the standard analyzer request and may need a
  custom adapter later.
- Legal/ToS: public data only; no login-as-user except the operator-provided X cookie.
