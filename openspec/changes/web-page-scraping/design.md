## Context

Canonical `social-scraper-api` (shared-specs @ 43df3d1, after #24 `remove-closed-platform-scraping` and #25 `llm-reply-retry` were archived) has two platforms, `bluesky` and `mastodon`. Every other URL fails with `unsupported_url` (`social-scraper-api/spec.md:59-72`).

Backend @ 88830ca (scraper code unchanged since dfe8c12): `internal/socialscraper/urls.go` `Recognize` maps a URL to a `Target` without network access and excludes only `bsky.app` from Mastodon recognition (`urls.go:23`); the Mastodon module returns `unsupported_url` when the host does not serve the Mastodon API (`internal/socialscraper/mastodon/mastodon.go:105`); `internal/scraper/scraper.go` `mapResult` builds `Job.input` from `post`/`posts` and treats any unknown `url_kind` like a profile (`scraper.go:113`). The job-level scrape timeout defaults to 120 s (`internal/engine/engine.go:154`, `SCRAPER_TIMEOUT`).

## Goals / Non-Goals

Goals: a `web`/`page` result that frontend, analyzers and backend can read concurrently; precise routing, error codes and input mapping. Non-goals: other providers, multi-page crawling, persistent cache, bypassing login walls.

## Decisions

### D1: Written against the canonical specs

This change MODIFIES canonical requirements (`URL normalization before recognition`, `Bluesky and Mastodon URLs`, `Unsupported URLs`, `ScrapeResult profile members`, `Request error codes`; analysis-jobs-api `Scraped input content`, `Scraped input source`, `Scrape failure causes`, `Scraper unavailable`, `Scrape failure outcomes`) and keeps every existing scenario name. Web behaviour is in new requirements (`Web page fallback`, `Page profile members`, `Local hosts not scraped`, `Mastodon probe fallback`, `Web page …` members, text, Markdown fallback, rendering and retries, cache, configuration error, error codes, login wall; analysis-jobs-api `Scraped page source`). No other change is active. `llm-reply-retry` (#25, now archived into canonical) changed different analysis-jobs-api requirements (FinalAssessment, LLM reply retry) and topic-extraction-result; none overlaps the requirements modified here, whose canonical text this delta keeps.

### D2: `login_required` re-introduced for `web` only

#24 removed `login_required` with the Instagram/Threads modules (archived). Login walls are the expected outcome for links to closed networks routed to `web`, and they must not look like `no_text_content` or `upstream_error`. A new requirement `Web page login wall` defines the code for `details.platform: web`, without `missing_settings`. Clients that kept handling `login_required` (#24 migration note) need no change.

### D3: Page result keeps the ScrapeResult shape

A `page` ScrapeResult has every existing member: profile members null, `posts: []`, `post: null`, `comments: []`, `warnings`. New members are flat (as in the issue's `metadata.scrape` list) and include `text`, so that `Job.input.content` is derived from the ScrapeResult like for posts. `username` becomes nullable only for `url_kind: page` (a new value); results of existing kinds are unchanged.

### D4: `source.url` uses the canonical URL only on the same registered domain

The issue asks for `canonical_url` or the final URL. `source_info.page_outlet` is looked up from `source.url`; a page could declare a reputable outlet as canonical and borrow its outlet record. Decision: `canonical_url` is used only when its registered domain equals the fetched page's `domain`; otherwise the `final_url`. The canonical URL is still in `metadata.scrape.canonical_url`. The requested URL is in `metadata.scrape.requested_url`. For profiles and posts `source.url` stays the requested URL.

### D5: `unsupported_url` narrowed to unsafe or unfetchable URLs

Routing: parse → safety checks (scheme, userinfo, length 2,000, `localhost`/`.localhost`, private/loopback/link-local/unspecified IP literals) → Bluesky shapes → Mastodon shapes (probe) → `web`. A Mastodon-shaped URL whose host does not serve the Mastodon API falls back to `web` in the same scrape (for example `medium.com/@alice`). `bsky.app` paths that are not a profile or post go to `web` without a Mastodon probe. The provider, not the server, fetches the page, so host names that resolve to private addresses are not resolved or checked by the server.

ScrapeRequest allows URLs up to 2,048 characters (analysis-jobs-api `Scrape request`); 2,001–2,048 characters are accepted at job creation and fail the scrape with `unsupported_url`. Kept as the issue specifies; no change to request validation.

### D6: Provider details in the contract only where clients see them

The contract names the provider (`provider: oxylabs`, `oxylabs_requests`) and the setting names in `details.missing_settings`, because they are visible in results and errors. Request shapes for the Oxylabs Web API / Web Scraper API, the extraction library, metadata precedence, cache key normalization, configuration defaults and timeouts are backend-local (backend task `local_requirements`).

### D7: Job scrape timeout

A rendered fetch needs a client timeout of at least 150 s. The backend raises the default job-level scrape timeout (`SCRAPER_TIMEOUT`) so that one unrendered fetch, one rendered fetch and one 429/5xx retry fit (backend-local; analysis-jobs-api already says the scrape fails with `timeout` when the server's scrape timeout ends).

## Compatibility classification

Usages found with `grep -rn` in canonical shared specs @ 43df3d1:

| Item | Where used | Change | Class |
|---|---|---|---|
| `ScrapeResult.platform` values | `social-scraper-api/spec.md:75` (`bluesky`, `mastodon`); mirrored by `Scrape.platform` `analysis-jobs-api/spec.md:263`, `Job.input.source.platform` `analysis-jobs-api/spec.md:288`; `analysis-job-events/spec.md:105` (Bluesky only) | adds `web` | shared-additive (new value in an "includes" list, tolerant reader `social-scraper-api/spec.md:20`) |
| `url_kind` values | `social-scraper-api/spec.md:42`, `analysis-jobs-api/spec.md:263` | adds `page` | shared-additive |
| ScrapeResult members | `social-scraper-api/spec.md:75,86` | new members for `page`; `username` null for `page` only | shared-additive (existing kinds unchanged) |
| Recognition / `unsupported_url` | `social-scraper-api/spec.md:59-72,117-122`; `analysis-jobs-api/spec.md:301-307` and the `Scrape failure outcomes` scenario | URLs that failed with `unsupported_url` are now scraped as `web` and succeed or fail with a web code | shared-breaking (an existing case changes outcome); wire-compatible, error codes are an "includes" list |
| Mastodon-shaped non-Mastodon hosts | `social-scraper-api/spec.md:49` | fall back to `web` instead of `unsupported_url` | shared-breaking (outcome), wire-compatible |
| `login_required` | not in canonical specs (removed by #24); tolerated as unknown code (`social-scraper-api/spec.md:20`) | produced again, `details.platform: web` | shared-additive (new value in an "includes" list) |
| `platform_not_configured`, `rate_limited`, `upstream_error`, `upstream_timeout` | `social-scraper-api/spec.md:151,162` | produced for `web`; new optional `details.target_status` | shared-additive |
| `no_text_content` | `analysis-jobs-api/spec.md:277,285,295` | also produced by the scraper for an empty page (same job outcome) | shared-additive |
| `Job.input.source` mapping | `analysis-jobs-api/spec.md:288` | for `page`: `url` canonical/final URL, `title`, `author`, `published_at` from the page | shared-additive (new kind only) |
| Valid ScrapeResult | `analysis-jobs-api/spec.md:310` | `page` needs string `text` | shared-additive (new kind only) |
| `source_info.page_outlet` | `source-info-result/spec.md:104` | unchanged rule; now has a `source.url` for scraped pages | none |
| Request validation scenarios with `https://x.com/alice` | `analysis-jobs-api/spec.md:237,245` | unchanged (validation, scraping disabled) | none |

Affected clients and migration:

- **frontend** @ 1abe19a: `grep -rn "platform\|source.title\|source.author" frontend/src` finds nothing; it shows no scrape platform, URL kind or scrape error code specially. No migration.
- **analyzers**: receive `$input.source` with `platform: web` and `metadata.scrape` page members; they already ignore unknown members. No migration.
- **project** @ 441ecbf: `full-e2e` is a placeholder without scraping tests. No migration.
- **Jobs created earlier** keep their recorded outcomes (for example `unsupported_url` for a news link). No data migration.

## Risks / Trade-offs

- [Paid provider cost] → at most 3 provider requests per scrape (unrendered, rendered, one 429/5xx retry), in-memory cache of successes, `oxylabs_requests` and `cached` recorded per scrape.
- [Login-wall heuristics] → false positives only for short pages with a password field; long pages never become `login_required`.
- [Fake outlet attribution through `canonical_url`] → D4.
