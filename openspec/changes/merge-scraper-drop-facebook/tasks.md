# Tasks

## 1. Shared contract
- [x] 1.1 social-scraper-api delta: in-process scraper, no HTTP endpoints, no Facebook
- [x] 1.2 analysis-jobs-api delta: scraping on unless disabled, in-process failure causes

## 2. Backend (child task backend-merge-scraper)
- [ ] 2.1 Implement per the child issue and its local OpenSpec change

## 3. Archive
- [ ] 3.1 On archive, replace the social-scraper-api Purpose with: "Contract of the social-media scraper that runs inside the orchestrator: given the URL of a public post or profile on a supported platform, it yields the author's profile, recent posting history and, for a post URL, the post and its comments, normalized across platforms, with typed error codes for every way a scrape can fail. Clients see it through jobs created with `scrape` (analysis-jobs-api)."
