# Qwen developer setup

Configuration lives in `ios/Boxing/Services/QwenDeveloperConfiguration.swift`: developer apiKey, compatible baseURL ending in `/v1`, textModel and visionModel. Values are now present. Never print credentials or commit them; the configuration file and device build output are excluded by .gitignore. Customers do not supply keys and provider names do not appear in product copy.

The native client appends `/chat/completions`, authenticates with the developer key, uses ephemeral uncached requests and exposes cancellation/errors. Missing or failed configuration never returns a canned response. Personal records persist only through local SwiftData; photos/selected frames are sent only by explicit requests.

- Training: full compatible catalog/context, seven-day typed response, JSON mode, local validation, one service correction attempt and explicit acceptance. Request timeout 150 seconds for long structured plans. Local civil date/weekday/availability metadata avoids UTC-midnight mistakes; a timezone change makes an old draft stale.
- Nutrition: AI-only fueling targets/energy estimate, editable preview, numerical checks and explicit acceptance. The user removed the earlier separate policy-review gate; no clinical review is claimed. See NUTRITION_POLICY.md.
- Food estimates, coach chat, catalog workout proposals and selected-frame video reviews retain their dedicated contracts. Saving an estimate does not turn it into verified nutrition or movement data.
- Non-thinking text requests reduce latency; training JSON mode still requires local checks. No reasoning text is shown or treated as a plan.

Live integration checks are opt-in via `BOX_RUN_AI_INTEGRATION=1` in Swift tests and use fictional profiles, not customer data. Training and nutrition targets passed live parsing/validation/acceptance. Earlier timeouts and invalid equipment/recovery drafts were caught; no rejected output was saved. Photo/video accuracy, younger-user dietary suitability, chat/workout-specific output and physical network behavior remain unverified.

Direct developer keys are **Debug-only**. Release AI remains disabled until an app-owned authenticated gateway is implemented. The gateway can call Qwen while durable training/food/media records remain on device. Do not distribute a shared provider secret in a release binary.

Official provider documentation checked 20 October 2026:
- https://docs.qwencloud.com/developer-guides/getting-started/first-api-call
- https://docs.qwencloud.com/developer-guides/text-generation/thinking
- https://docs.qwencloud.com/developer-guides/text-generation/structured-output

Use the endpoint/model actually enabled for the developer account. No competitor credentials/endpoints are used. Other integrations: barcode contact remains deliberately unset in Services/BarcodeLookup.swift; StoreKit IDs remain empty and purchases disabled in Services/SubscriptionStore.swift.
