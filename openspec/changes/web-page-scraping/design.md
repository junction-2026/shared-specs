## Context

Canonical `social-scraper-api` (shared-specs @ 6d1e0c0) and the active change `remove-closed-platform-scraping` (feature junction-2026/project#24, published, implementation pending: backend @ 1574bd3 still has the Instagram, Threads and X modules) together leave two platforms, `bluesky` and `mastodon`. Every other URL fails with `unsupported_url` (#24 delta `Unsupported URLs`).

Backend @ 1574bd3: `internal/socialscraper/urls.go` `Recognize` maps a URL to a `Target` without network access; the Mastodon module returns `unsupported_url` when the host does not serve the Mastodon API (`internal/socialscraper/mastodon/mastodon.go:105`); `internal/scraper/scraper.go` `mapResult` builds `Job.input` from `post`/`posts` and treats any unknown `url_kind` like a profile (`scraper.go:111`). The job-level scrape timeout defaults to 120 s (`internal/engine/engine.go:153`, `SCRAPER_TIMEOUT`).

## Goals / Non-Goals

Goals: a `web`/`page` result that frontend, analyzers and backend can read concurrently; precise routing, error codes and input mapping. Non-goals: other providers, multi-page crawling, persistent cache, bypassing login walls, removing the social modules (#24).

## Decisions

### D1: Builds on `remove-closed-platform-scraping`, archived after it

#24's implementation has started, so its change is not edited. This change MODIFIES the requirements as #24 leaves them (`URL normalization before recognition`, `Bluesky and Mastodon URLs`, `Unsupported URLs`, `ScrapeResult profile members`, analysis-jobs-api `Scrape failure causes`) and requirements #24 does not touch (`Request error codes`, `Scraped input content`, `Scraped input source`, `Scraper unavailable`, `Scrape failure outcomes`). It does not modify requirements that exist only in #24's delta (for example `Upstream and internal error codes`); web behaviour is in new requirements (`Web page fallback`, `Page profile members`, `Local hosts not scraped`, `Mastodon probe fallback`, `Web page …` members, text, Markdown fallback, rendering and retries, cache, configuration error, error codes, login wall; analysis-jobs-api `Scraped page source`). The change id sorts after #24's, so the archive dry-run and the final archive apply #24 first. If this feature is archived first, #24's MODIFIED blocks would overwrite the `web` texts; the orchestrator re-plans this feature if #24 is archived before this plan is published, and this plan must not be archived before #24.

### D2: `login_required` re-introduced for `web` only

#24 removes `login_required` with the Instagram/Threads modules. Login walls are the expected outcome for links to closed networks routed to `web`, and they must not look like `no_text_content` or `upstream_error`. A new requirement `Web page login wall` defines the code for `details.platform: web`, without `missing_settings`. Clients that kept handling `login_required` (#24 migration note) need no change.

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

Usages found with `grep -rn` in canonical shared specs @ 6d1e0c0 and in the active #24 delta:

| Item | Where used | Change | Class |
|---|---|---|---|
| `ScrapeResult.platform` values | `social-scraper-api/spec.md:70` (#24 delta: `bluesky`, `mastodon`); mirrored by `Scrape.platform` `analysis-jobs-api/spec.md:263`, `Job.input.source.platform` `analysis-jobs-api/spec.md:288`; `analysis-job-events/spec.md:105` (Bluesky only) | adds `web` | shared-additive (new value in an "includes" list, tolerant reader `social-scraper-api/spec.md:20`) |
| `url_kind` values | `social-scraper-api/spec.md:38`, `analysis-jobs-api/spec.md:263` | adds `page` | shared-additive |
| ScrapeResult members | `social-scraper-api/spec.md:70,77` | new members for `page`; `username` null for `page` only | shared-additive (existing kinds unchanged) |
| Recognition / `unsupported_url` | `social-scraper-api/spec.md:59-67,120-124` (#24 delta `Unsupported URLs`); `analysis-jobs-api/spec.md:300-303,315-317` | URLs that failed with `unsupported_url` are now scraped as `web` and succeed or fail with a web code | shared-breaking (an existing case changes outcome); wire-compatible, error codes are an "includes" list |
| Mastodon-shaped non-Mastodon hosts | `social-scraper-api/spec.md:45` (#24 delta) | fall back to `web` instead of `unsupported_url` | shared-breaking (outcome), wire-compatible |
| `login_required` | canonical `social-scraper-api/spec.md:167-194`, removed by #24 | produced again, `details.platform: web` | shared-additive relative to #24 (code clients already tolerate) |
| `platform_not_configured`, `rate_limited`, `upstream_error`, `upstream_timeout` | `social-scraper-api/spec.md:142,153` (#24 delta) | produced for `web`; new optional `details.target_status` | shared-additive |
| `no_text_content` | `analysis-jobs-api/spec.md:277,285,295` | also produced by the scraper for an empty page (same job outcome) | shared-additive |
| `Job.input.source` mapping | `analysis-jobs-api/spec.md:288` | for `page`: `url` canonical/final URL, `title`, `author`, `published_at` from the page | shared-additive (new kind only) |
| Valid ScrapeResult | `analysis-jobs-api/spec.md:306` | `page` needs string `text` | shared-additive (new kind only) |
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
- [Order with #24] → D1.
- [Fake outlet attribution through `canonical_url`] → D4.
