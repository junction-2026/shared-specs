# Proposal: Social-media scraping as job input

## Why

Parent feature junction-2026/project#8: the bot and propaganda analyzers need real
social-media content, but a job's input today is plain text only
(analysis-jobs-api "Input object", "Create job"). Analysts want to submit the URL of
a post or profile and have the system fetch the post, its comments, the author's
profile and posting history, then analyze it.

Based on: backend @ fbf9e6f6763158047ae9c0eceaa65e7aec8cb5b5 (Go orchestrator with
the merged project#6 LLM finalizer; no scraper code; `internal/job`, `internal/httpapi`,
`internal/finalizer`), frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (health
page only; no client of `/api/v1/jobs`), project @
441ecbf96961128099af004da50a063f18b3345c (`full-e2e` is a placeholder), shared-specs @
729fe96720e155868fb944c773470ac4619779f0 (active change `llm-finalizer-verdict` of
project#6, approved to run in parallel; no requirement modified by both changes, see
design.md decision 7).

## What Changes

- **social-scraper-api** (new capability): the scraper service's HTTP API —
  `GET /health` (no auth), `POST /scrape {url, max_posts, max_comments}` with Bearer
  auth, recognized URLs for Bluesky, Mastodon, Instagram, Threads, Facebook pages and
  X, the normalized ScrapeResult (flat profile members as in the handover draft plus
  `url_kind`, `post`, `comments`, `warnings`, `scraped_at`), plain-text normalization,
  partial results with warnings, and typed errors (`unsupported_url`,
  `unsupported_account_type`, `account_not_found`, `post_not_found`,
  `account_private`, `rate_limited`, `platform_not_configured`, `upstream_error`,
  `upstream_timeout`, `unauthorized`, `validation_failed`, `internal_error`).
- **analysis-jobs-api**
  - `POST /api/v1/jobs` accepts `scrape: {url, max_posts, max_comments}` instead of
    `input`; 422 when both or neither are given; 503 `scrape_unavailable` when no
    scraper is configured.
  - Job gains `scrape` (Scrape object, null for text jobs); `input` is null until the
    scrape succeeds (only for jobs created with `scrape`).
  - New job status `scraping`; `failed` also covers a failed scrape.
  - New AnalyzerRun skip reason and finalization skip reason `input_unavailable`.
  - New requirements: Scrape object, Scraped input mapping (ScrapeResult → Input,
    full result in `source.metadata.scrape`), Scrape failure outcomes, Cancellation
    during scraping.
- **analysis-job-events**: new events `scrape.started`, `scrape.succeeded`,
  `scrape.failed`; `job.started`, settle-event ordering and the finalization barrier
  are restated for scrape jobs.

Not changed: text jobs (every existing request and response stays valid),
analyzer-service-protocol (analyzers receive the scraped data through the existing
`$input` / `$input.source` bindings), api-conventions.

## Decisions for approval

- **Scraper home:** a Python FastAPI service in the backend repository under
  `scraper/` (own Dockerfile, tests and CI job), because only backend, frontend and
  project are registered repositories, the handover draft and the platform libraries
  (atproto, instaloader, twscrape, Playwright) are Python, and the backend owns the
  only caller. Its API is still a shared contract because it is reachable by outside
  clients through Traefik.
- **Asynchronous scrape inside the job** (status `scraping`) instead of scraping in
  the `POST` request, since Facebook/Playwright and rate limits can take far longer
  than an HTTP request should wait.
- **No frontend task:** the frontend has no job submission form yet; URL input will
  come with that form in a later feature.

## Impact

- backend: scraper service (`scraper/`), orchestrator scrape phase, config
  `SCRAPER_URL`, `SCRAPER_TOKEN`, `SCRAPER_TIMEOUT`, example bot-detection analyzer.
- frontend, project: no change in this feature.
