## ADDED Requirements

### Requirement: Scraping available by default
Scraping SHALL be available by default in the backend, with no separately running scraper service or scraper-specific configuration.

#### Scenario: Single backend scrapes
- **WHEN** a backend started without scraper-specific configuration receives `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social"}}`
- **THEN** the status is 201 and the job's scrape runs inside that backend

## MODIFIED Requirements

### Requirement: Scrape request validation
`POST /api/v1/jobs` SHALL respond 422 `validation_failed` when both or neither of `input` and `scrape` are present (`details.fields` key `input`) or when `scrape.url`, `scrape.max_posts` or `scrape.max_comments` is missing where required, of the wrong type or out of range. It SHALL respond 503 `scrape_unavailable`, creating no job, for a body with `scrape` only when scraping is disabled in the server's configuration.

#### Scenario: Both input forms
- **WHEN** a client posts `{"input": {"content": "x"}, "scrape": {"url": "https://x.com/alice"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `input`

#### Scenario: Invalid scrape URL
- **WHEN** a client posts `{"scrape": {"url": "ftp://example.com/a"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `scrape.url`

#### Scenario: Scraper not configured
- **WHEN** the server has scraping disabled in its configuration and a client posts `{"scrape": {"url": "https://x.com/alice"}}`
- **THEN** the status is 503 with `error.code` `scrape_unavailable` and no job is created

### Requirement: Scrape failure causes
A scrape SHALL fail when the scraper yields a scrape error (social-scraper-api), yields a result that is not a valid ScrapeResult, or does not finish within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `internal_error`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` MUST NOT contain tokens, cookies or other platform credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper fails with `account_private` and `details.platform` `instagram`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: instagram`

#### Scenario: Facebook URL
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`

### Requirement: Scraper unavailable
`Scrape.error.code` SHALL be `scraper_unavailable` when the scraper fails with `internal_error` (for example a panic in a platform module) or yields a result that is not a valid ScrapeResult (missing `platform` or `url_kind`, or `url_kind: post` without `post`).

#### Scenario: Scraper down
- **WHEN** a platform module panics while scraping a job's URL
- **THEN** the job's `scrape.error.code` is `scraper_unavailable`, the job ends `failed` and the server keeps serving other jobs
