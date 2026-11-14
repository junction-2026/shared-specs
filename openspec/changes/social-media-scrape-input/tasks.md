# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add capability `social-scraper-api`
- [x] 1.2 Add URL-based job creation, Scrape object, `scraping` status and failure outcomes to `analysis-jobs-api`
- [x] 1.3 Add scrape events and restate lifecycle ordering in `analysis-job-events`
- [x] 1.4 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend scraper service (children `backend-scraper-core`, `backend-scraper-meta-platforms`, `backend-scraper-fb-x`)
- [ ] 2.1 Core service: auth, health, request validation, URL recognition for all platforms, error envelope, Bluesky and Mastodon
- [ ] 2.2 Instagram and Threads modules with recorded fixtures
- [ ] 2.3 Facebook pages and X modules with recorded fixtures

## 3. Backend orchestrator (child `backend-scrape-job-input`)
- [ ] 3.1 `scrape` request member, validation and `scrape_unavailable`
- [ ] 3.2 Scrape phase, input mapping, failure and cancellation outcomes, events
- [ ] 3.3 Tests against a stub scraper; bot-detection example config
