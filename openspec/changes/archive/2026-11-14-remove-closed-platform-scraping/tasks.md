## 1. Shared contract

- [ ] 1.1 Review and approve the delta specs for `social-scraper-api` and `analysis-jobs-api`
- [ ] 1.2 Publish the change on shared-specs `main` (no archive until the feature integrates)

## 2. Backend (child `backend-remove-closed-platform-scrapers`)

- [ ] 2.1 Remove the Instagram, Threads and X modules, their registration, URL recognition, settings and redaction entries
- [ ] 2.2 Limit Mastodon host exclusion to `bsky.app`
- [ ] 2.3 Update tests, README and local specs; run `go test ./...` and the OpenSpec validation

## 3. Frontend and project

- [ ] 3.1 No change: verified at frontend @ 1abe19a and project @ 441ecbf that nothing reads removed platform values or removed error codes
