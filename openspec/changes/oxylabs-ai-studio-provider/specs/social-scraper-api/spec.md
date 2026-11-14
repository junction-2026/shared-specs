## MODIFIED Requirements

### Requirement: Web page fallback
Every URL that passes the checks of Unsupported URLs and is not a Bluesky or Mastodon URL SHALL be recognized as `platform: web`, `url_kind: page` and scraped through the server's configured page provider: an Oxylabs HTML provider (Web API or Web Scraper API, `provider: oxylabs`) or Oxylabs AI Studio (`provider: oxylabs_ai_studio`). A `web` scrape makes no request to the target site from the server itself.

#### Scenario: News article
- **WHEN** a job scrapes `https://www.dw.com/en/some-article/a-12345678` on a server with an Oxylabs HTML provider configured
- **THEN** the ScrapeResult has `platform: web`, `url_kind: page` and `provider: oxylabs`

#### Scenario: News article through AI Studio
- **WHEN** a job scrapes `https://www.dw.com/en/some-article/a-12345678` on a server configured for Oxylabs AI Studio
- **THEN** the ScrapeResult has `platform: web`, `url_kind: page` and `provider: oxylabs_ai_studio`

#### Scenario: Bluesky still a platform
- **WHEN** a job scrapes `https://bsky.app/profile/alice.bsky.social/post/3kxyz`
- **THEN** the ScrapeResult has `platform: bluesky` and no provider request is made

### Requirement: Web page fetch members
A `page` ScrapeResult SHALL have at least: `truncated` (boolean); `extraction` (values include `trafilatura`, `markdown_fallback` and `ai_studio_json`); `rendered` (boolean, true when fetched with JavaScript rendering); `cached` (boolean, true when served from the server's page cache); `provider` (values include `oxylabs` and `oxylabs_ai_studio`); `oxylabs_requests` (integer, requests sent to the provider for this scrape, `0` when `cached`; see AI Studio run budget).

#### Scenario: Fetch members of a fresh scrape
- **WHEN** a page is scraped for the first time through an HTML provider and one unrendered fetch yields its text
- **THEN** the ScrapeResult has `rendered: false`, `cached: false`, `provider: "oxylabs"`, `oxylabs_requests: 1` and `extraction: "trafilatura"`

#### Scenario: Fetch members of an AI Studio scrape
- **WHEN** a page is scraped for the first time through AI Studio, its run is polled three times and its JSON result has a body longer than the minimum text length
- **THEN** the ScrapeResult has `rendered: true`, `cached: false`, `provider: "oxylabs_ai_studio"`, `oxylabs_requests: 1` and `extraction: "ai_studio_json"`

### Requirement: Web page Markdown fallback
For an HTML provider: when the main content extracted from the HTML is shorter than the server's minimum text length (default 300 characters) even after a rendered fetch, and the provider's Markdown version of the page has more text, `text` SHALL be that Markdown with its syntax removed and `extraction` SHALL be `markdown_fallback`; otherwise `extraction` is `trafilatura`.

#### Scenario: Markdown fallback
- **WHEN** no main content can be extracted from the HTML even after a rendered fetch, and the provider's Markdown has 800 characters of text
- **THEN** the scrape succeeds with `extraction: "markdown_fallback"` and `text` without Markdown syntax such as `#`, `**` or `[label](url)` link targets

### Requirement: Web page rendering and retries
For an HTML provider, a `web` scrape SHALL first fetch the page without JavaScript rendering; if the main content extracted from it is shorter than the minimum text length, it SHALL fetch once more with rendering and use that answer (`rendered: true`). A provider answer HTTP 429 or 5xx SHALL be retried at most once per scrape; there SHALL be no other retries, so a scrape sends at most 3 provider requests.

#### Scenario: Rendering retry
- **WHEN** an HTML provider returns a JavaScript shell without article text for the unrendered fetch and the full article for the rendered fetch
- **THEN** exactly two provider requests are sent, the ScrapeResult has `rendered: true`, `oxylabs_requests: 2` and the full article `text`

#### Scenario: No rendering needed
- **WHEN** the unrendered fetch of an HTML provider yields 1,500 characters of main content
- **THEN** exactly one provider request is sent and the ScrapeResult has `rendered: false` and `oxylabs_requests: 1`

### Requirement: Web page configuration error
A `web` scrape SHALL fail with `platform_not_configured`, `details.platform` `web` and `details.missing_settings` naming the missing provider settings, before any provider request, when the provider credentials are not configured: `OXYLABS_WEB_API_KEY` for the default Oxylabs Web API, `OXYLABS_USERNAME` and/or `OXYLABS_PASSWORD` for the Oxylabs Web Scraper API, `OXYLABS_AI_STUDIO_API_KEY` for Oxylabs AI Studio.

#### Scenario: Provider not configured
- **WHEN** `OXYLABS_WEB_API_KEY` is not set and a job scrapes `https://www.dw.com/en/some-article/a-12345678`
- **THEN** the scrape fails with `error.code` `platform_not_configured`, `details.platform` `web` and `details.missing_settings` containing `OXYLABS_WEB_API_KEY`, and no provider request is made

#### Scenario: AI Studio not configured
- **WHEN** the server is configured for Oxylabs AI Studio without `OXYLABS_AI_STUDIO_API_KEY` and a job scrapes `https://www.dw.com/en/some-article/a-12345678`
- **THEN** the scrape fails with `error.code` `platform_not_configured`, `details.platform` `web` and `details.missing_settings` containing `OXYLABS_AI_STUDIO_API_KEY`, and no provider request is made

### Requirement: Web page login wall
A `web` scrape SHALL fail with `login_required` and `details.platform` `web`, without `details.missing_settings`, when the main text is shorter than the minimum text length after the rendered fetch and the page shows a login wall: a password input, a log-in or sign-in form as main content, or a final URL path `/login`, `/signin` or `/accounts/login` (or below them). For AI Studio, see AI Studio login and paywall pages. The server does not bypass login walls.

#### Scenario: Social network login wall
- **WHEN** a job scrapes `https://www.instagram.com/nasa/` and the provider returns a page with a password input and almost no other text
- **THEN** the scrape fails with `error.code` `login_required`, `details.platform` `web` and no `details.missing_settings`

#### Scenario: Short page without login wall
- **WHEN** the rendered page has 120 characters of main text and no login-wall marker, and its Markdown has no more text
- **THEN** the scrape succeeds with that `text`

#### Scenario: Not a retry condition
- **WHEN** a client shows a job whose scrape failed with `login_required`
- **THEN** it does not present it as a missing page or as a wait-and-retry condition

## ADDED Requirements

### Requirement: AI Studio extraction
With AI Studio, the server SHALL first start one rendered JSON run that extracts the page's metadata, its classification (article, post, other content, login wall, error page, consent or paywall) and its main body. `text` SHALL be that body with `extraction: ai_studio_json` and `rendered: true`; metadata members are filled from the same run, while `host` and `domain` are always computed by the server from `final_url`.

#### Scenario: AI Studio article
- **WHEN** the AI Studio JSON run returns a 3,000-character body for an article with site name `DW`
- **THEN** the scrape succeeds with `text` equal to that body (after removal of control and zero-width characters), `site_name: "DW"`, `extraction: "ai_studio_json"`, `rendered: true` and `oxylabs_requests: 1`

### Requirement: AI Studio Markdown fallback
With AI Studio, when the JSON run fails, or returns a body shorter than the minimum text length for a page classified as article, post or other content, the server SHALL start one rendered Markdown run and, when it has text, use it with its Markdown syntax removed and `extraction: markdown_fallback`.

#### Scenario: AI Studio Markdown fallback
- **WHEN** the AI Studio JSON run returns a 50-character body for an article and the Markdown run returns 5,000 characters of text
- **THEN** the scrape succeeds with `provider: "oxylabs_ai_studio"`, `extraction: "markdown_fallback"`, `rendered: true` and `oxylabs_requests: 2`

### Requirement: AI Studio run budget
An AI Studio scrape SHALL start at most 2 runs and `oxylabs_requests` SHALL count runs started, not status polls or result downloads. Each run is bounded by the server's rendered-fetch timeout and stops when the job is cancelled.

#### Scenario: AI Studio run budget
- **WHEN** the AI Studio JSON run fails and the Markdown run also fails
- **THEN** no third run is started and the scrape fails

#### Scenario: Polls not counted
- **WHEN** an AI Studio JSON run is polled three times before it completes with a long body
- **THEN** the ScrapeResult has `oxylabs_requests: 1`

### Requirement: AI Studio errors
A failed AI Studio scrape SHALL set `details.platform` `web` and use: `upstream_error` when a run ends in a failure status, with the optional `details.provider_error_code` (string) set to the provider's error code when it gave one; `upstream_timeout` when a run has not completed within the rendered-fetch timeout; `no_text_content` when the page is classified as an error page or has an empty body and no fallback text. No error SHALL contain a provider credential.

#### Scenario: AI Studio run failed
- **WHEN** both AI Studio runs of a scrape end in a failure status with `error_code` `target_unreachable`
- **THEN** the scrape fails with `error.code` `upstream_error`, `details.platform` `web` and `details.provider_error_code` `target_unreachable`

#### Scenario: AI Studio run never completes
- **WHEN** an AI Studio run is still processing when the rendered-fetch timeout elapses
- **THEN** the scrape fails with `error.code` `upstream_timeout` and `details.platform` `web`

#### Scenario: AI Studio error page
- **WHEN** the AI Studio JSON run classifies the page as an error page with an empty body
- **THEN** the scrape fails with `error.code` `no_text_content` and `details.platform` `web`

### Requirement: AI Studio login and paywall pages
With AI Studio, a `web` scrape SHALL fail with `login_required` and `details.platform` `web`, without `details.missing_settings`, when the JSON run classifies the page as a login wall, or as a consent or paywall page whose body is shorter than the minimum text length; in the latter case `message` says the page is behind a consent or paywall.

#### Scenario: AI Studio paywall
- **WHEN** the AI Studio JSON run classifies the page as a consent or paywall page with a 100-character body
- **THEN** the scrape fails with `error.code` `login_required`, `details.platform` `web` and a `message` saying the page is behind a consent or paywall
