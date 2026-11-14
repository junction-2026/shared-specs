# Design: Russian localization language

Based on backend @ d03c1cc, frontend @ 16b0a12, project @ 441ecbf, shared-specs @ 9a26edb.

## Current state
- Shared: job-text-localization/spec.md:9 (endpoint, `unsupported_language` with `details.supported`),
  :21 (scenario: supported includes en, fr, ar, de, fi), :24 (supported languages "include" en, fr, ar, de, fi;
  primary-subtag matching), :64-70 (orchestrator fixed text from the deployment's fixed translation).
- Backend: `internal/localization/localization.go:22` `Supported = en, fr, ar, de, fi`; `:32-38` fixed translations
  of `finalizer.InsufficientText`; `TestFixedTableCoversSupported` (localization_test.go:110) requires a fixed text
  per supported language. The provider prompt (provider.go:16) names the target language by ISO 639-1 code, so it
  needs no language-name table. `internal/engine/activity.go:36-39` (`languageNames`) and the technique glossary
  (`internal/adapter/technique_glossary.go:19`) already include `ru`.
- Frontend: `src/i18n/locales.ts` declares the locales; `src/api/client.ts:49` sends the active UI locale as
  `language`; `src/job/localize.tsx:74` names `source_language` with `Intl.DisplayNames`, which covers `ru`.

## Decisions
1. `ru` is added to the tolerant enumeration "SHALL include"; the list stays "includes", never "exactly".
2. Russian is matched like the other codes (primary subtag, case-insensitive); no special handling of
   `ru-RU`/`ru-UA` etc.
3. The Russian orchestrator fixed text is a fixed, first-pass translation shipped by the backend; it is not produced by
   a model call (unchanged requirement "Orchestrator fixed text").
4. No shared requirement on UI locales: the frontend `i18n` capability is local to the frontend.

## Compatibility classification

| Changed item | Used at (canonical spec) | Change | Class |
|---|---|---|---|
| Supported localization languages | job-text-localization/spec.md:24 ("SHALL include") | adds `ru` | shared-additive: the set is an "includes" enumeration; a client never sent `ru` expecting 400 |
| `unsupported_language` `error.details.supported` | job-text-localization/spec.md:9, :21; api-conventions error envelope | list gains `ru` | shared-additive: clients read it as "includes" |
| `GET /api/v1/jobs/{id}/localization?language=ru` | job-text-localization/spec.md:9 | 400 `unsupported_language` becomes 200 JobLocalization | shared-additive: a newly supported value of an existing parameter; the only client (frontend) sends `ru` only after it adds the `ru` locale |
| JobLocalization / LocalizedText objects | job-text-localization/spec.md:27-48 | none | — |

No shared-breaking change; no client migration.

## Rollout / ordering
- Backend first: `ru` is accepted; nobody requests it until the frontend ships `ru`.
- Frontend first: a `ru` UI requests `language=ru`, gets 400 `unsupported_language` until the backend ships; the
  frontend already treats a failed localization like unavailable texts (original shown, marked as not in the UI
  language). No break, so the tasks are independent.
