## MODIFIED Requirements

### Requirement: Scrape failure causes
A scrape SHALL fail when the scraper yields a scrape error (social-scraper-api), yields a result that is not a valid ScrapeResult, or does not finish within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `internal_error`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` MUST NOT contain tokens, cookies or other platform credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper fails with `account_private` and `details.platform` `mastodon`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: mastodon`

#### Scenario: Facebook URL
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`

#### Scenario: Unsupported social network URL
- **WHEN** a job is created with `{"scrape": {"url": "https://x.com/alice"}}` on a server with scraping enabled
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable`
