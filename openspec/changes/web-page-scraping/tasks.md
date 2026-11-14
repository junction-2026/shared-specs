## 1. Shared contract

- [ ] 1.1 Review and approve the delta specs for `social-scraper-api` and `analysis-jobs-api`
- [ ] 1.2 Publish the change on shared-specs `main` (no archive until the feature integrates)

## 2. Backend (child `backend-web-page-scraping`)

- [ ] 2.1 Add the `web` module (Oxylabs Web API, optional Web Scraper API builder, extraction, metadata, cache) and its configuration
- [ ] 2.2 Route unclaimed http(s) URLs and non-Mastodon hosts to `web`; narrow `unsupported_url` to the safety checks
- [ ] 2.3 Map `url_kind: page` results into the job input
- [ ] 2.4 Offline tests with fixtures and a stub provider; README; local OpenSpec change; `go test ./...` and OpenSpec validation

## 3. Frontend and project

- [ ] 3.1 No change: verified at frontend @ 1abe19a and project @ 441ecbf that nothing reads scrape platform values, URL kinds or scrape error codes
