## 1. Shared contract
- [ ] 1.1 Approve new capability `term-context-result`

## 2. backend (child `backend-term-context`)
- [ ] 2.1 Registry entry and config for `term_context` (defaults, `depends_on`, category `coverage`)
- [ ] 2.2 Term selection LLM call, validation, verbatim-substring filter, de-duplication, cap and order
- [ ] 2.3 `in_post` sentence extraction; `elsewhere` snippet matching with letter/digit boundaries
- [ ] 2.4 Wikipedia title lookup (redirects, search fallback, disambiguation), lead quote, revision permalink, cache
- [ ] 2.5 Comparison LLM call over quotes only; `sense` and `differs_from` validation; `unknown` without a call
- [ ] 2.6 Failures, credential hiding, progress activity; tests and README

## 3. frontend (child `frontend-term-cards`)
- [ ] 3.1 Tolerant reader of the TermContext result
- [ ] 3.2 Term cards: `in_post`, encyclopedia quote, elsewhere snippets, sense; links only per the rendering rule;
  labels in all UI locales
