# Tasks

## 1. Shared contract (this change)
- [x] 1.1 Define api-conventions, analysis-jobs-api, analysis-job-events, analyzer-service-protocol delta specs
- [x] 1.2 Validate with `scripts/validate-openspec.sh` (strict + archive dry-run)
- [ ] 1.3 Human approval and publish to shared-specs main (not archived)

## 2. backend-engine (backend repo, local change `backend-analysis-engine`)
- [ ] 2.1 Job model incl. Coverage, Finalization and FinalAssessment types matching analysis-jobs-api
- [ ] 2.2 Analyzer registry loader and validation, applicability, selection with transitive dependencies
- [ ] 2.3 `http_sync`, `http_async` and `custom` adapters per analyzer-service-protocol
- [ ] 2.4 DAG scheduler with timeouts, failure propagation, skip reasons, cancellation, settle barrier hook
- [ ] 2.5 Per-job ordered event bus with seq numbers and event types of analysis-job-events

## 3. backend-api (backend repo, local change `backend-analysis-http-api`)
- [ ] 3.1 REST endpoints and error envelope per analysis-jobs-api and api-conventions
- [ ] 3.2 WebSocket endpoint with snapshot-on-connect, ordering and close codes per analysis-job-events
- [ ] 3.3 `cmd/orchestrator` wiring, configuration, Dockerfile

## 4. backend-finalizer (backend repo, local change `backend-analysis-finalizer`)
- [ ] 4.1 `after_all_analyzers_settled` trigger, exactly-once finalization on the settle barrier
- [ ] 4.2 Finalizer invocation via adapters, FinalAssessment validation, insufficient-evidence short-circuit
- [ ] 4.3 Finalization events, timeout and cancellation handling; `job.completed` only after finalization ends
