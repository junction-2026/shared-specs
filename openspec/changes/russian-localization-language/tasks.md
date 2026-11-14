# Tasks

## 1. Shared contract
- [x] 1.1 Delta spec for `job-text-localization`: supported languages and `unsupported_language` details include `ru`.
- [x] 1.2 Compatibility classification in design.md.

## 2. backend (child `backend-russian-localization`)
- [ ] 2.1 Add `ru` to `localization.Supported`.
- [ ] 2.2 Russian fixed translation of `finalizer.InsufficientText`.
- [ ] 2.3 Tests: `ru`/`RU`/`ru-RU` accepted, `details.supported` includes `ru`, orchestrator fixed text in Russian without a provider call, existing languages unchanged.

## 3. frontend (child `frontend-russian-locale`)
- [ ] 3.1 Declare `ru` (Русский, ltr) in `src/i18n/locales.ts`.
- [ ] 3.2 Russian catalogs for every namespace of `en` with `_one/_few/_many/_other` plural forms.
- [ ] 3.3 Tests: completeness covers `ru`, detection of `ru-RU`, `<html lang="ru" dir="ltr">`, plural forms, formatters.
