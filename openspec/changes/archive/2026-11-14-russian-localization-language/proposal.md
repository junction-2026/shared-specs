# Russian (ru) as a supported localization language (junction-2026/project#60)

Based on backend @ d03c1cc4ce1f941ef37a4b715c2de081ac65f379, frontend @ 16b0a127095cb2c5815b67ea9f3ac1cadea76ffd,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 9a26edb52efa7e1ee9a46eea7721be73f67b50b7.

## Why
The platform UI and the job-text localization endpoint support `en`, `fr`, `ar`, `de` and `fi`
(job-text-localization/spec.md:24). Russian-speaking users get the UI in English and
`GET /api/v1/jobs/{id}/localization?language=ru` answers 400 `unsupported_language`.

## What changes (shared interface)
- `ru` joins the supported localization languages of `GET /api/v1/jobs/{id}/localization`. It is matched like the
  others: case-insensitively by its primary subtag (`ru-RU`, `RU` mean `ru`), and `JobLocalization.language` is `"ru"`.
- `error.details.supported` of `unsupported_language` includes `ru`.
- The orchestrator fixed text (`produced_by: orchestrator`) is served in Russian from the deployment's fixed
  translation, without a model call (existing "Orchestrator fixed text" requirement, now covering `ru`).

Nothing else in the API changes: no new member, endpoint or error code.

## Not in the shared change (local to the owning repository, rule 13)
- frontend: `ru` locale declaration (label `Русский`, ltr), Russian catalogs for every namespace, plural forms,
  detection/persistence, formatter coverage, tests (frontend local change `frontend-russian-locale`).
- backend: `Supported` list, Russian fixed insufficient-evidence text, tests (backend local change
  `backend-russian-localization`).

## Impact
- Capability: `job-text-localization` (MODIFIED "Get job localization", "Localization languages").
- Clients: the frontend is the only client; it requests its UI locale, so `ru` is requested only once the frontend
  ships the `ru` locale. Either repository can ship first (see design.md).
