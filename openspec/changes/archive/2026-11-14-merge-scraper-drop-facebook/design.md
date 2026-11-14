# Design: in-process scraper, no Facebook, no Chromium

## Context

Today the orchestrator calls `POST {SCRAPER_URL}/scrape` with `Authorization: Bearer
{SCRAPER_TOKEN}` (backend `internal/scraper/scraper.go`), and `cmd/scraper` serves the
shared social-scraper-api on port 8003 from `scraper.Dockerfile` (Debian + Chromium for
the Facebook module). Without `SCRAPER_URL` a `scrape` job answers 503
`scrape_unavailable`.

## Decisions

1. **In-process call, no HTTP endpoints.** The engine calls the scraper core
   (`internal/socialscraper`) directly. `GET /health` / `POST /scrape` are not kept on the
   merged binary: once the scraper image is gone, keeping them would add a new
   authenticated public endpoint to the orchestrator API for no registered client
   (frontend and project contain no reference to the scraper). The orchestrator keeps its
   own `/healthz`. Alternative rejected: mounting `/scrape` on the orchestrator under a
   bearer token (adds a second auth scheme to `/api/v1`'s server and a new contract).
2. **Scraping on by default.** A single backend must scrape without extra setup
   (acceptance criterion of #14). Scraping is disabled only by backend configuration
   (backend-local, `SCRAPER_ENABLED=false`); then `scrape` jobs answer the existing 503
   `scrape_unavailable`.
3. **Error contract unchanged for clients.** Error codes of the scraper reach clients only
   through `Job.scrape.error`. `internal_error` (panic or unexpected failure in a platform
   module) and an invalid result still become `scraper_unavailable`, as today.
   `unauthorized`, `invalid_request`, `validation_failed` cannot occur anymore (no HTTP hop;
   the ScrapeRequest is validated by `POST /api/v1/jobs`).
4. **Facebook removal**: URL recognition no longer knows `facebook`; such URLs fall to the
   generic `unsupported_url` path (`facebook.com` is not a Mastodon host: the Mastodon
   recognizer must not probe it — backend-local requirement).
5. **Purpose text.** The canonical Purpose of social-scraper-api says "HTTP API of the
   social-media scraper service"; delta specs cannot change it. The archiver SHALL replace
   it at archive time (tasks.md 3.1).

## Compatibility classification (evidence: canonical specs @ 8324422)

| Change | Where used | Class |
|---|---|---|
| Remove `GET /health`, `POST /scrape`, bearer auth, request validation | social-scraper-api spec.md:8-52; only caller backend `internal/scraper` | shared-breaking for standalone-service callers; none in registered repos; migration below |
| Remove Facebook URLs / platform `facebook` | social-scraper-api spec.md:75-80; analysis-jobs-api spec.md:263 (`platform` "as in social-scraper-api") | shared-breaking (a former success becomes `unsupported_url`); platform values are an "includes" list (spec.md:16), frontend has no Facebook reference |
| Drop `unsupported_account_type` | social-scraper-api spec.md:140-144; analysis-jobs-api spec.md:295 (pass-through) | shared-breaking only in that the code is no longer produced; tolerant readers unaffected |
| Drop HTTP statuses and `Retry-After` header from scraper error codes | social-scraper-api spec.md:133-173 | not observable by clients after the merge (codes and `details` unchanged) |
| Scraping available without `SCRAPER_URL` | analysis-jobs-api spec.md:234, 244-246 | shared-additive (503 kept for disabled scraping) |
| `scraper_unavailable` / failure-cause wording | analysis-jobs-api spec.md:295-306 | same codes, same meaning for clients |
| `fact-check-result` spec.md:91 "Facebook-Beitrag" | claimant text in an example, not platform support | unchanged |

## Migration

- Deployments stop running the scraper container; delete it and its Traefik route.
- `SCRAPER_URL`, `SCRAPER_TOKEN`, `SCRAPER_LISTEN_ADDR` are ignored by the merged backend
  (startup warning naming the variable, no abort), so existing env files keep starting.
- `TWITTER_AUTH_TOKEN`, `TWITTER_CT0`, `INSTAGRAM_SESSION_FILE`,
  `SCRAPER_UPSTREAM_TIMEOUT_SECONDS` and `SCRAPER_TIMEOUT` move to the orchestrator
  container with unchanged names and meaning.
- Facebook URLs now fail with `unsupported_url`.
