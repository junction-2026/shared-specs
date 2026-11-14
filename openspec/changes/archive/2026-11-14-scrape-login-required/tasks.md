# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add `login_required` to social-scraper-api error codes; narrow `account_not_found`/`post_not_found`, `rate_limited` and the Threads `upstream_error` scenario
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-scrape-login-required`)
- [ ] 2.1 `LoginRequired(platform, msg, missing...)` in `internal/socialscraper/errors.go`
- [ ] 2.2 Instagram: anonymous 404 -> `login_required` with `missing_settings: ["INSTAGRAM_SESSION_FILE"]`; login wall -> `login_required`; 429 stays `rate_limited`
- [ ] 2.3 Threads: fetch from `https://www.threads.com`; login-wall page -> `login_required`; other data-less page -> `upstream_error` naming what was missing
- [ ] 2.4 README error list and limitation notes; stub-only tests; no browser dependency
