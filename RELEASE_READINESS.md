# BOX: release readiness — 25 October 2026

Status of every area that must be resolved before an App Store release, in priority order. "P0" blocks release; "P1" should ship in v1 or the first update; "P2" can follow later.

## Where the product stands

Working on device today: the redesigned app (Train, Review, Today, Fuel, Progress), guided rounds, the drill and exercise catalog (now including hooks, uppercuts, slips, ducks, combinations, a camera sparring round and dumbbell strength work), live pads (jab/cross), sparring mode with game effects, camera drills for every new move, the unified program builder (training week + nutrition, reviewed and accepted together), food logging with AI estimates, clip recording and AI clip review, coach chat, and local history/progress.

Verified only in tests or the simulator: the recognition of hooks, uppercuts, slips and ducks (synthetic motion through the full pipeline, no confusion between moves), the sparring engine, camera drills inside guided sessions, and the program builder UI. **None of the new detection has been measured on a real body yet.**

## P0 — must fix before release

1. **AI provider key is inside the app binary.** Update 26 Oct: the app now uses the Vercel proxy (no key sent) and has on-device rate limits; still add server-side limits/App Attest to the Qwen route and rotate the key. `QwenDeveloperConfiguration.apiKey` is compiled into every build. It is git-ignored, but anyone with the app can extract it and spend on your account. Build a small server gateway (authenticates the app, holds the key, rate-limits per user, hides the provider) and point `QwenClient` at it. **Rotate the current key**: it has also appeared in a development session log.
2. **Real-world recognition accuracy.** Run Detection check on device for every move in both stances, at 1.5–3 m, in good and poor light, with different clothing. Target before release: ≥90% per move recognised as asked, no move misread as another more than 5% of the time, and fewer than 1 false move per idle minute. Tune `MoveRecognizer.Tuning` from the results. Record a small labelled clip set (the Review tab can already tag clips) so future changes can be regression-tested on real footage, not only synthetic motion.
3. **Thermal and battery.** MoveNet Thunder runs on the CPU at up to 24 fps. Measure a full 3-round sparring session on an older supported iPhone: thermal state, battery drain, dropped frames. If it heats up, switch to the Lightning model or a Neural Engine model (Apple Vision) when `ProcessInfo.thermalState` rises.
4. **Five failing unit tests.** `ActivityCatalogTests` still asserts live pads and recognition are switched off (stale since they shipped). Update it to the current capability registry. `PadTrainingTests.liveRoundsUseOnlyActiveTimeAndEndAfterConfiguredRest` fails on rounds timing. Investigate it, because it may be a real bug in Live pads rounds mode.
5. **Onboarding.** There is no first-run flow. New users land on Today with no profile, stance, schedule or program. Add a short onboarding (goal, experience, stance, days, camera permission with a framing tutorial) that ends in the program builder.
6. **Privacy and App Store compliance.** Done today: the camera purpose string now describes live recognition, and a privacy manifest declares the UserDefaults reason. Still needed: a privacy policy and terms; App Store privacy labels that match what is sent to the AI service (messages, training history, profile, body measurements, food photos, clip frames); the collected data types in `PrivacyInfo.xcprivacy` once the gateway exists; an AI-processing consent screen; and an age rating with handling for under-18 users (nutrition already restricts targets for minors).
7. **Coach review of content.** Every drill says "pending boxing-coach review". A qualified coach must review drill instructions, combination cues, the sparring choreography and safety copy before launch.
8. **Subscriptions.** StoreKit products, paywall, free vs paid limits, and App Store Connect configuration are not set up (`SubscriptionView` shows "setup in progress"). Decide pricing and gate features before submission.
9. **Data safety.** Update 26 Oct: iCloud sync built (needs a two-device test). Everything is local SwiftData with no restore: losing or replacing the phone loses all history, plans and targets. Add iCloud (CloudKit) sync or, at minimum, backup and restore on top of the existing export.
10. **Crash reporting and analytics.** There is no crash reporting or product analytics, so device crashes in the field would be invisible. Add a privacy-respecting crash reporter and a few key events (session started/finished, detection-check results, program accepted), declared in the privacy labels.

## P1 — v1 or the first update

1. **Progression: XP, levels and ranks.** Done 25 Oct: derived XP, 12 ranks, 21 awards, celebrations. Still open: rank unlocks (sparring difficulties, harder combos), per-move skill meter, weekly goals.
2. **Adaptive program.** Done 26 Oct (adaptive summary, effort ratings, Build next week). The program is built one week at a time and rebuilt by hand. Generate next week automatically from completion, sparring accuracy and feedback, with a short review step.
3. **Reminders.** Notifications for scheduled training days (currently "Reminders are not enabled").
4. **Apple Health.** Write workouts and energy to Health; optionally read heart rate from Apple Watch during rounds.
5. **Sparring audio.** Sound effects for hits, misses and streaks, an optional beat or music track, and spoken combo calls. It is haptics-only today, and sound is a big part of the "addictive" feel.
6. **Sparring polish.** Your focus-mitt artwork (`Design/Art/pad-mitt.png`), a per-device timing calibration, difficulty that adapts to accuracy, and a daily challenge. Leaderboards need a backend or Game Center.
7. **Strength workouts fully in one catalog.** The older ready-made routines in `WorkoutRoutine` still live apart from the activity catalog the program builder uses. Move them into the catalog so there is one source for all exercise.
8. **Accessibility.** VoiceOver and large-text passes on the camera arenas and the program builder; respect Reduce Motion in the sparring effects.
9. **Localization.** Strings are English-only; move them into a String Catalog before adding languages.

## P2 — later

- Game Center achievements and friend leaderboards, shareable score cards.
- Widgets and Live Activities for rounds in progress.
- Apple Watch companion.
- iPad layout.
- A learned, on-device move classifier trained on consented, labelled clips (see `research/recognition/EVALUATION_PLAN.md`) to replace or back up the rule-based recogniser.

## Suggested order

Gateway + key rotation → device Detection check and tuning → fix the five tests → onboarding → progression (XP/levels) → privacy/legal and subscriptions → coach content review → TestFlight with 10–20 testers for two weeks → submit.
