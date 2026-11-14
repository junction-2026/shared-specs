# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Add capability `source-info-result`
- [x] 1.2 Classify every affected use (design.md) and validate with `scripts/validate-openspec.sh`

## 2. Backend (child `backend-source-info`)
- [ ] 2.1 Outlet table loader with header, duplicate host/domain and empty `domain` validation (row named)
- [ ] 2.2 Registry: `adapter: source_info`, `execution.outlets_file`, startup failure when enabled and the file is missing or invalid
- [ ] 2.3 Adapter: matching (host, then registered domain), SourceArticle list, `page_outlet`, summary, table, `no_sources` skip
- [ ] 2.4 Dockerfile `COPY data/outlets.csv`; `docs/examples/source_info.yaml`
- [ ] 2.5 Tests: 5-row CSV matching, startup validation, summary, page outlet, skip, real data file
