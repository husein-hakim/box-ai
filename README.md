# BOX — native iPhone development build

Original boxing companion. Start with BUILD_HANDOFF.md, BUILD_STATUS.md and FEATURE_CHECKLIST.md. Only virtual sparring is deferred.

Open `ios/Boxing.xcodeproj`, scheme **Boxing**, select Husein's iPhone 17 (or a simulator), then Run. Signing team BG8YSU2SAM is configured for the user's connected device. First signed install/launch succeeded; ongoing physical checks are recorded in BUILD_STATUS.md. The phone must remain connected, trusted and unlocked during installation. No third-party package is required.

Working increments include guided audio rounds, local SwiftData profile/preferences/history, manual meals/macros/water/targets, foundation weekly planning, resumable manual workout checklists, local video capture/import/playback/notes and manual interval annotations and typed Qwen frame-review requests. AI integrations are separate: Qwen chat, food estimates and constrained plan proposals need developer configuration and live verification. All training measurements remain timer/manual records, without invented punch recognition or technique scores.

Add developer Qwen settings in `ios/Boxing/Services/QwenDeveloperConfiguration.swift`; exact instructions and release-gateway requirement are in QWEN_SETUP.md. Customers never enter provider keys. Offline manual features work without them.

The app uses local SwiftData without CloudKit. Video files live in local app storage with SwiftData metadata. JSON export covers records, not embedded video; restore/import is not built yet. Explicit AI requests disclose and send their necessary context to Qwen.

Run `swift test` for domain/persistence checks. In a restricted execution environment, see the local build status for limitations; the verified run used `swift test --disable-sandbox` to avoid a nested SwiftPM sandbox, without disabling the host sandbox. Current suite: 23 tests.

The approved UI uses native typography, SF Symbols, charcoal surfaces and red actions, without hero images. Source: `design/today-reference.png`; earlier Today evidence: `design/qa`. Research/decompiled reference material stays outside the shipped target. No Baller code, assets, copy or credentials are included.
