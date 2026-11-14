## Why

Clients and the LLM finalizer only see `status: skipped` plus a machine `reason` for an analyzer that did not run. They cannot tell "there was nothing for this analyzer to check" (for example `no_checkable_claims`) from "the analyzer broke". The finalizer then writes "the fact-check tool was unavailable" for posts that simply contain no factual claims, and the UI can only say "skipped". Parent: junction-2026/project#22.

## What Changes

- **Additive**: every AnalyzerRun gains two members, `availability` (`ran` | `not_applicable` | `unavailable`, `null` while not settled) and `note` (short fixed English sentence, `null` when `availability` is `null` or `ran`).
- A fixed, documented mapping from `status` / `reason` / `error.code` to `availability` and `note`, including resolution of `dependency_skipped` to the root skipped dependency.
- The members appear wherever an AnalyzerRun is serialized: `GET /api/v1/jobs/{id}`, `POST /api/v1/jobs`, `POST /api/v1/jobs/{id}/cancel`, `data.analyzer` of `analyzer.*` events and the `$job.analyzers` binding. Existing members (`status`, `reason`, `error`, ...) are unchanged.
- No new skip reason, no change to Coverage, verdict semantics or the insufficient-evidence rule.

Out of the shared contract (backend-local, see design.md): the LLM finalizer entry format (`llmEntries`) and the base prompt `config/finalizer/prompt.md` rules.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `analysis-jobs-api`: new requirements "AnalyzerRun availability", "Availability note text", "Nothing-to-check skips", "Input and selection skips", "Unavailable runs", "Dependency-skipped availability" and "Availability stability" (AnalyzerRun object gains `availability` and `note`).

## Impact

- Based on backend @ 17240e21aba872338b4f0a0fe65fdcd40a13e138, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 485829deb6e9db092802c56efe9c441e719ece8a.
- backend: computes the members (one mapping function shared by the API and the LLM finalizer) and updates the finalizer prompt.
- frontend: no change required (tolerant reader; it does not render AnalyzerRuns today). Rendering the note is an optional follow-up.
- Event and analyzer-service-protocol payloads carry the new members through their existing reference to the AnalyzerRun object; their specs need no text change.
