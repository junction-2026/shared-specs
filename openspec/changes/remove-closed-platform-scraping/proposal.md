## Why

The scraper recognizes Instagram, Threads and X/Twitter URLs and documents platform-specific failures for them (`login_required`, `platform_not_configured` for X). These platforms cannot be scraped reliably without breaking their terms of service or paying for expensive APIs (junction-2026/project#24). Only Bluesky and Mastodon, which have open, documented public APIs, stay supported.

Based on backend @ 34e1c514854bb0d191b70c2a8bfef83333326959, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 2bda20ae4aebdb404c7a3035ed9d31df44d5ea54.

## What Changes

- **BREAKING (behaviour)** `social-scraper-api`: URLs of Instagram, Threads, X/Twitter and Facebook are no longer special-cased. They are recognized only if they match the Bluesky or the generic Mastodon URL shapes, like any other host; otherwise they fail with `unsupported_url`.
- `social-scraper-api`: the `platform` value list is `bluesky`, `mastodon` (still an "includes" list; clients keep tolerating unknown values, including values recorded on jobs created before this change).
- `social-scraper-api`: the `Instagram and Threads URLs`, `X URLs`, `Login required error code` and `Login required details` requirements are removed. `login_required` is no longer produced.
- `social-scraper-api`: `platform_not_configured` stays in the error-code list as a generic code (a recognized platform without a module or without required credentials on this server); the X example is dropped. With Bluesky and Mastodon it is not expected in normal operation.
- `social-scraper-api`, `analysis-jobs-api`: scenarios that used removed platforms are rewritten with Bluesky, Mastodon or unsupported URLs.
- No request, response or object shape changes. No new endpoint, member or error code.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `social-scraper-api`: supported platforms, URL recognition, error codes and scenarios.
- `analysis-jobs-api`: `Scrape failure causes` scenarios only.

## Impact

- backend: removes the Instagram, Threads and X modules, their URL recognition, settings (`INSTAGRAM_SESSION_FILE`, `TWITTER_AUTH_TOKEN`, `TWITTER_CT0`), docs, tests and local specs; reserves only `bsky.app` from Mastodon probing.
- frontend: no change. At 1abe19a, `frontend/src` has no reference to scrape platform values, `login_required`, `platform_not_configured` or `missing_settings`.
- project: no change. The `full-e2e` suite is a placeholder and has no scraping test.
