## Context

Based on backend @ 17240e21aba872338b4f0a0fe65fdcd40a13e138, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, shared-specs @ 485829deb6e9db092802c56efe9c441e719ece8a.

Skip reasons in use today: canonical `disabled`, `not_selected`, `not_applicable`, `dependency_failed`, `dependency_skipped`, `cancelled`, `input_unavailable` (analysis-jobs-api spec.md:81); capability-specific `no_checkable_claims` (fact-check-result spec.md:38), `no_searchable_topics` (news-search-result spec.md:24), `no_sources` (source-info-result spec.md:28). Failed runs carry `error.code` (`timeout`, `adapter_error`, `invalid_output`, `cancelled`, ...).

## Goals / Non-Goals

Goals: one server-computed classification per AnalyzerRun that both the finalizer and clients use. Non-goals: changing `status`/`reason`/`error` values, Coverage (`applicable` keeps counting e.g. `no_checkable_claims` runs as applicable), the insufficient-evidence rule, or adding skip reasons.

## Decisions

1. **Two new members, not a new reason.** `availability` is a coarse class, `note` is display text. `reason` stays the machine detail. Alternative (new reasons) rejected: breaking for clients that switch on reasons and against the non-goal.
2. **Mapping table** (normative copy is in the delta spec):
   - `succeeded` -> `ran`, note null.
   - skipped `no_checkable_claims` / `no_searchable_topics` / `no_sources` / `not_applicable` -> `not_applicable` with a reason-specific note.
   - skipped `not_selected` / `disabled` -> `not_applicable`, "Not run: this analyzer was not requested for this job."
   - skipped `dependency_skipped` -> the values of the root skip (first skipped id in `depends_on` order, recursively, max depth 8).
   - `failed` (any code), skipped `dependency_failed`, `cancelled`, `input_unavailable` and any unknown reason -> `unavailable`, generic note.
   - `pending` / `running` -> both null.
3. **Computed once at settle time.** A dependency is always settled before its dependent settles, so the value is final when the run settles and is identical in the settle event and in later GETs; it never changes afterwards (consistent with "a settled AnalyzerRun SHALL never change").
4. **Notes are fixed English display text**, not an API enum. Clients must not parse them; wording may be revised without a contract change. Clients that localise switch on `availability` and `reason`.
5. **Tolerant reader.** Unknown future `availability` values SHALL be treated like `unavailable`.

## Compatibility classification

| Object / place | Spec evidence | Change | Class |
|---|---|---|---|
| AnalyzerRun object | analysis-jobs-api spec.md:73-74 ("at least") | + `availability`, + `note` | shared-additive |
| Job.analyzers (GET/POST job, cancel) | analysis-jobs-api spec.md:45, 67 | carries the AnalyzerRun | shared-additive |
| `analyzer.*` events `data.analyzer` | analysis-job-events spec.md:34 | carries the AnalyzerRun | shared-additive |
| `$job.analyzers` binding (http finalizers) | analyzer-service-protocol spec.md:30 | carries the AnalyzerRun | shared-additive |
| JobSummary (`GET /api/v1/jobs`) | analysis-jobs-api spec.md:160 | no AnalyzerRun, unchanged | none |

No removed/renamed member, type or meaning change; no breaking change. No existing "exactly" clause is touched.

## Backend-local (not in this contract)

The LLM finalizer entry (`{id, description, status, result?, reason?}` in `internal/finalizer/finalizer.go`) gains `availability` and `note`, and the prompt `config/finalizer/prompt.md` gets the new availability and `uncertain` rules. These are the backend's private interface with its configured LLM and are specified in the backend task's local change (`analysis-finalizer`).

## Risks / Trade-offs

- `cancelled`/`input_unavailable` get the generic "failed or is not set up" note, which is imprecise; acceptable per the parent issue (unknown -> unavailable). Clients wanting precision use `reason`.
- Coverage `applicable` and `availability: not_applicable` differ for capability-specific skips; documented here, unchanged by design.
