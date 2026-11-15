## 1. Shared contract
- [ ] 1.1 Publish `focus` on ChatRequest, ChatFocusItem, references, validation, resolution and focused answers in `analysis-chat-api`

## 2. Backend (child issue, local change `chat-focus-backend`)
- [ ] 2.1 Parse and validate `focus` with the existing ChatRequest validation
- [ ] 2.2 Resolve items against the job and pass them to the assistant as a server-owned data message
- [ ] 2.3 Tests: validation, resolution per kind, unresolved items, prompt content, injection through labels

## 3. Frontend (child issue, local change `ask-veil-split-focus`)
- [ ] 3.1 Split-pane Ask VEIL page with selectable result elements and selection chips
- [ ] 3.2 Send `focus` with each question; show per-turn focus in the thread; i18n and RTL
- [ ] 3.3 Tests: none/one/many selection, payload, retry, responsive layout, RTL
