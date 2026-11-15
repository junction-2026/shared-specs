## 1. Shared contract
- [ ] 1.1 Approve the new capability `bot-detection-result` (ADDED requirements)

## 2. backend (child `backend-bot-text`)
- [ ] 2.1 `bot_detection` text adapter: original `normalized_content` to the detector, label mapping, validation, failure codes
- [ ] 2.2 Registry example `docs/examples/bot_detection.yaml`, `llm.description`, README, risk-config comment
- [ ] 2.3 Tests with a stub detector (original text sent, translation not sent, label mapping, malformed answers, unchanged risk/propaganda)

## 3. frontend (child `frontend-bot-text-marker`)
- [ ] 3.1 Tolerant reader of the `bot_detection` text result
- [ ] 3.2 Marker next to the confidence in the verdict card with tooltip / aria text; hidden when unavailable
- [ ] 3.3 Catalog texts for every locale; component tests
