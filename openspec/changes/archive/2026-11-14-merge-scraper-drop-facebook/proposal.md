# Proposal: Merge the scraper into the orchestrator; drop Facebook and Chrome

## Why

Parent feature junction-2026/project#14. The scraper is a separate binary
(`cmd/scraper`) and image (`scraper.Dockerfile`, Debian + Chromium) next to the
orchestrator image. Only one image is supported. Facebook is the only module that needs
Chromium (chromedp) and is not supported for now.

Based on: backend @ c9d39e4ae1902f33669bdb0f5112361b35625308 (`cmd/scraper`,
`internal/socialscraper/*`, `internal/scraper` HTTP client, `cmd/orchestrator/config.go`),
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (no mention of the scraper, scraping
or Facebook: nothing to change), project @ 441ecbf96961128099af004da50a063f18b3345c (no
compose file or suite references the scraper image), shared-specs @
8324422d6348be58949a9f3149d7d6a772f7e94f (no active shared change).

## What Changes

- **social-scraper-api** (modified): the scraper runs **inside the orchestrator** and
  serves no HTTP API of its own. **BREAKING for direct callers of the standalone
  service**: `GET /health`, `POST /scrape`, its bearer authentication and its request
  validation are removed (no registered repository calls them; the only caller was the
  orchestrator's `internal/scraper` client). The capability keeps the contract every
  client still sees through `POST /api/v1/jobs` with `scrape`: recognized URLs, the
  ScrapeResult (embedded verbatim in `source.metadata.scrape`), warnings and the scrape
  error codes (passed through in `Job.scrape.error`). HTTP statuses of the old endpoint
  are dropped from the error codes; `rate_limited` keeps `details.retry_after_s`.
- **social-scraper-api** (modified): **Facebook removed**. `facebook.com` URLs are
  `unsupported_url`; platform `facebook` is no longer produced; `unsupported_account_type`
  (only produced for Facebook personal profiles) is no longer produced. X recognition is
  unchanged and moves to its own requirement.
- **analysis-jobs-api** (modified): scraping is available unless the server disables it
  by configuration (503 `scrape_unavailable` unchanged in shape); scrape failure causes and
  `scraper_unavailable` are reworded for an in-process scraper. The set of
  `Scrape.error.code` values clients may see is unchanged except that
  `unsupported_account_type` no longer occurs.

Not changed: ScrapeRequest, Scrape object, Job input mapping, events, data shape for
Bluesky, Mastodon, Instagram, Threads and X, no frontend work.

## Impact

- backend: one task (merge, Facebook/Chromium removal, config, CI, docs, local specs).
- frontend, project: none.
- Deployments: the scraper container and `SCRAPER_URL`/`SCRAPER_TOKEN` are obsolete; see
  design.md "Migration".
