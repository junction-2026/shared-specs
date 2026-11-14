## Why

Scrape jobs (`{"scrape": {"url": ...}}`) only work for Bluesky and Mastodon since junction-2026/project#24 removed the other social platforms. News articles, blogs and every other link fail with `unsupported_url`, although `source_info` already looks up `input.source.url` and would give outlet, country and leaning for news pages. junction-2026/project#26 adds a generic `web` platform: any other http(s) page is fetched through a paid scraping provider (Oxylabs), its main text and metadata are extracted, and the normal analysis runs on that text.

Based on backend @ dfe8c12b98ebd33cbd038c8863e9086f09718618, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ ee96c66b2ae1ddc6d3ccd8580fff23865568454b (canonical specs after #24 was archived).

## What Changes

- `social-scraper-api`: new platform value `web` with new URL kind `page`. Every absolute http(s) URL that no platform claims, including a Mastodon-shaped URL whose host does not serve the Mastodon API and URLs of unsupported social networks, is scraped as `web`/`page` instead of failing with `unsupported_url`.
- `social-scraper-api`: `unsupported_url` is narrowed to URLs that cannot be fetched safely: not absolute http(s), with userinfo, longer than 2,000 characters, or naming `localhost` or a private, loopback, link-local or unspecified IP literal.
- `social-scraper-api`: a `page` ScrapeResult has new members (`text`, `requested_url`, `final_url`, `host`, `domain`, `site_name`, `title`, `description`, `lang`, `canonical_url`, `published_at`, `author`, `word_count`, `truncated`, `extraction`, `rendered`, `cached`, `provider`, `oxylabs_requests`); its profile members are null and `posts`/`comments` are `[]`, `post` is null.
- `social-scraper-api`: error codes for `web`: `login_required` (login wall, re-introduced for `web` only; #24 removed it), `no_text_content`, `upstream_error`, `upstream_timeout`, `rate_limited`, `platform_not_configured` with `details.missing_settings` naming the provider settings.
- `analysis-jobs-api`: input mapping for `url_kind: page` (`content` = `text`; `source.url` = canonical URL when on the fetched page's registered domain, otherwise the final URL; `source.title`, `source.author`, `source.published_at` from the page); a `page` result without a string `text` is not a valid ScrapeResult; scenarios that used `example.com` or Facebook as unsupported URLs are rewritten.
- No request shape changes, no new endpoint. All result changes are additive members or new values in "includes" lists, except the URLs that used to fail with `unsupported_url` and now succeed or fail with another code (see design.md).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `social-scraper-api`: `web` platform, `page` URL kind, page result members, web error codes, narrowed `unsupported_url`.
- `analysis-jobs-api`: scraped input content and source for pages, scrape result validity, rewritten scenarios.

## Impact

- backend: new `web` scrape module (Oxylabs Web API client, optional Web Scraper API request builder, go-trafilatura extraction, metadata extraction, in-memory cache), routing fallback in URL recognition, page mapping in the job input, configuration (`OXYLABS_*`), README, offline tests with fixtures.
- frontend: no change. At 1abe19a, `frontend/src` has no reference to scrape platform values, URL kinds, `source.platform` or scrape error codes.
- project: no change. The `full-e2e` suite is a placeholder without scraping tests; tests must not call the real provider.
