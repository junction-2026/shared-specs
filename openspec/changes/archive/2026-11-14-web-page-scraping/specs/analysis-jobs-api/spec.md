## MODIFIED Requirements

### Requirement: Scraped input content
When a job's scrape succeeds, the orchestrator SHALL set `Job.input` from the ScrapeResult (social-scraper-api) before any analyzer starts, with `content_type` `text/plain` and `content` the `post.text` for `url_kind: post`, the `text` for `url_kind: page`, or for `url_kind: profile` the non-empty `text` of `posts`, newest first, joined with `\n\n`. If that `content` is blank after trimming, the scrape SHALL fail with `error.code` `no_text_content` instead.

#### Scenario: Profile history as content
- **WHEN** a profile scrape returns posts with texts `B` (newest), `` and `A`
- **THEN** the job's `input.content` is `B\n\nA`

#### Scenario: Post without text
- **WHEN** the scraped post is an image with an empty caption
- **THEN** the scrape is `failed` with `error.code` `no_text_content` and the job ends `failed`

#### Scenario: Page text as content
- **WHEN** a `web` page scrape returns `text` `First paragraph.\nSecond paragraph.`
- **THEN** the job's `input.content` is `First paragraph.\nSecond paragraph.` and `input.content_type` is `text/plain`

### Requirement: Scraped input source
For a scraped input, `source.platform` SHALL be the ScrapeResult `platform` and `source.metadata` `{"scrape": <the ScrapeResult verbatim>}`. For `url_kind` `profile` and `post`, `source.url` SHALL be the requested URL, `source.author` the `username`, `source.title` the `display_name` when not null, and `source.published_at` the `post.created_at` of a `post` when not null. For `page`, see Scraped page source. Analyzers binding `$input` or `$input.source` thereby receive the scraped data.

#### Scenario: Post URL mapped to input
- **WHEN** the scraper returns `url_kind: post`, `platform: mastodon`, `username: alice@mastodon.social` and `post.text` `Vote no!`
- **THEN** the job's `input` has `content: "Vote no!"`, `source.platform: mastodon`, `source.author: alice@mastodon.social` and `source.metadata.scrape` equal to the ScrapeResult

### Requirement: Scrape failure causes
A scrape SHALL fail when the scraper yields a scrape error (social-scraper-api), yields a result that is not a valid ScrapeResult, or does not finish within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `internal_error`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` and `error.details` MUST NOT contain tokens, cookies, API keys or other credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper fails with `account_private` and `details.platform` `mastodon`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: mastodon`

#### Scenario: Facebook URL
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}` and the page provider returns a login wall
- **THEN** the job ends `failed` with `scrape.error.code: login_required` and `scrape.error.details.platform: web`

#### Scenario: Unsupported social network URL
- **WHEN** a job is created with `{"scrape": {"url": "https://x.com/alice"}}` on a server whose page provider is not configured
- **THEN** the job ends `failed` with `scrape.error.code: platform_not_configured`, `scrape.error.details.platform: web` and every selected AnalyzerRun `skipped` with `input_unavailable`

#### Scenario: Login wall passed through
- **WHEN** a job scrapes `https://www.instagram.com/nasa/` and the page provider returns a login wall
- **THEN** the job ends `failed` with `scrape.error.code: login_required` and `scrape.error.details.platform: web`

#### Scenario: Unsupported URL
- **WHEN** a job is created with `{"scrape": {"url": "http://127.0.0.1/admin"}}` on a server with scraping enabled
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable`

### Requirement: Scraper unavailable
`Scrape.error.code` SHALL be `scraper_unavailable` when the scraper fails with `internal_error` (for example a panic in a platform module) or yields a result that is not a valid ScrapeResult (missing `platform` or `url_kind`, `url_kind: post` without `post`, or `url_kind: page` without a string `text`).

#### Scenario: Scraper down
- **WHEN** a platform module panics while scraping a job's URL
- **THEN** the job's `scrape.error.code` is `scraper_unavailable`, the job ends `failed` and the server keeps serving other jobs

### Requirement: Scrape failure outcomes
When a scrape fails other than by cancellation, every `pending` AnalyzerRun SHALL be `skipped` with reason `input_unavailable`, `finalization` SHALL be `skipped` with reason `input_unavailable`, the finalizer SHALL NOT be called (no insufficient-evidence assessment is produced), `input` SHALL stay null and the job SHALL end `failed`.

#### Scenario: Unsupported platform
- **WHEN** a job is created with `{"scrape": {"url": "http://localhost/article"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable` and `finalization` `skipped` with `input_unavailable`

## ADDED Requirements

### Requirement: Scraped page source
For a scraped input with `url_kind: page`, `source.url` SHALL be the ScrapeResult `canonical_url` when it is not null and its registered domain equals the ScrapeResult `domain`, otherwise its `final_url`. `source.title`, `source.author` and `source.published_at` SHALL be the ScrapeResult `title`, `author` and `published_at` when not null, and absent otherwise.

#### Scenario: Page mapped to input
- **WHEN** a job scrapes `https://www.dw.com/en/some-article/a-12345678?utm_source=x` and the ScrapeResult has `canonical_url` `https://www.dw.com/en/some-article/a-12345678`, `domain` `dw.com`, `title` `Election results`, `author` `Jane Doe` and `published_at` `2026-11-13T07:30:00Z`
- **THEN** the job's `input.source` has `url: "https://www.dw.com/en/some-article/a-12345678"`, `platform: web`, `title: "Election results"`, `author: "Jane Doe"`, `published_at: "2026-11-13T07:30:00Z"` and `metadata.scrape` equal to the ScrapeResult

#### Scenario: Canonical URL on another domain ignored
- **WHEN** a page fetched with `final_url` `https://copycat.example/story` declares `canonical_url` `https://www.dw.com/en/story/a-1`
- **THEN** the job's `input.source.url` is `https://copycat.example/story`, so `source_info.page_outlet` is looked up for `copycat.example`

#### Scenario: Outlet of a news page
- **WHEN** a job scrapes a `dw.com` article and the deployment's outlet table lists `dw.com` as Deutsche Welle
- **THEN** `source_info.page_outlet` is the Deutsche Welle outlet (source-info-result)
