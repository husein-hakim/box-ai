# Next development pass

Prepared 20 October 2026 after inspecting BUILD_STATUS.md, FEATURE_CHECKLIST.md and the current SwiftData, camera, catalog and Qwen implementation. This is a continuation plan, not a claim that the increments below have been implemented or tested.

## Preserve settled decisions

- Continue in this workspace and preserve the approved charcoal/red SwiftUI UI.
- Native iPhone app; durable personal records in SwiftData; recordings/media in protected local files indexed by SwiftData. No login or CloudKit database. All features free during development.
- Full companion scope remains: personal plans, technique/footwork/defense/combination drills, guided sessions, strength/conditioning/mobility workouts, nutrition/macros/water, progress/calendar/rewards, video review, contextual coach and future subscriptions.
- Qwen is the developer-configured cloud AI provider. End users never provide keys. Deterministic totals, scheduling, validation and timers stay local; live recognition stays on-device. Local storage does not make explicitly submitted Qwen context local processing.
- Interactive pad/reaction coaching is in scope. A tactical virtual opponent/full fight simulation remains deferred. A camera-first pad coach is the current design direction to prototype, not a finished design or a chosen recognition architecture.

## What already exists

Consult BUILD_STATUS.md and inspect code before touching a feature. Existing connected work includes SwiftData/manual food and water, foundation scheduling, original sample drills, six support workouts, guided callouts/checkpoint recovery, local camera/import/playback/annotations and typed Qwen chat/food/plan/workout/frame-review flows. Physical recording and corrected upright playback were user-confirmed in the earlier build chat. Live Qwen, trained recognition and 3D coach do not work yet; do not relabel existing UI as completed AI.

## Recommended order

### 1. Make the existing AI flows usable

Use the existing developer configuration in `ios/Boxing/Services/QwenDeveloperConfiguration.swift` and `QWEN_SETUP.md`. Developer supplies region/workspace endpoint, key and enabled text/vision model IDs. Do not request customer keys, copy competitor secrets or print credentials. Keep the existing Debug-only direct configuration. Release credentials belong behind an app-owned gateway; that gateway need not become a user-record database.

Before credentials arrive, verify contracts with clearly isolated test fixtures and improve errors/retry/cancellation without claiming live service success. Once configured, exercise real chat, text/photo food, plan, workout and selected-frame review on-device; validate proposed outputs before user acceptance and SwiftData saving. Verify saved results survive relaunch. Keep manual flows usable offline.

### 2. Start the camera-first live pad prototype early

Create a separate live-training surface using the full-screen front-camera preview. Add framing/calibration guidance, stance-aware stable pad targets, prepared/spoken callouts and explicit pause/recovery. Use simple original targets initially. Confirm orientation, preview cropping and mirroring alignment on the physical phone.

Extend camera capture with timestamped frame delivery and bounded processing; the current movie recorder is not a live recognizer. Keep camera/per-frame state out of broad SwiftUI invalidation paths. Coordinate capture, recording, interruption and cleanup instead of opening competing camera sessions.

This first milestone may run unscored while recognition is absent. Label it as such. Do not infer a punch from its requested cue, a timer or a wrist overlapping a circle. Record cue-visible timestamps separately from frame/event timestamps.

### 3. Resolve recognition with real data

Read `research/recognition/EVALUATION_PLAN.md` and the BoxMaxxing classifier/camera reports. BoxMaxxing is a reference for pose → motion candidates + temporal classifier → exercise judge; it is not evidence of measured accuracy, permission to redistribute weights or an already selected architecture for BOX.

Build the collection/labeling/pose-extraction/evaluation tooling using original consented footage. Include jab/cross, reset, ordinary movement and uncertain visibility. Compare learned pose and RGB baselines on matching person/setup-disjoint data; compare pose sources as needed. No benchmark claims without trained/exported candidates and physical-device measurements. Do useful capture/evaluation work before a full dataset exists; identify required footage/model resources concretely when reached.

Integrate a validated candidate into cue → observed response → judgment → feedback → next cue. Judge against the time the cue actually became visible. Handle uncertainty separately from an incorrect response. Save measured events/summaries in SwiftData; do not persist each frame as a database transaction. Technique corrections require separately supported evidence.

### 4. Broaden the daily training experience alongside model work

Expand the two sample drills into an original curriculum covering stance/guard, straight punches/combinations, footwork, defense and supported bag/pad work, with explicit equipment, space, level and time metadata. Add demonstrations when original assets are available. Mark coach-review status accurately.

Improve planning and progression using this catalog, validated local constraints and Qwen proposals/rationale. Build the timed/set workout player and complete nutrition targets/trends, calendar/challenges/reminders and restore/import increments. Target arithmetic follows an explicit reviewed policy; Qwen can explain it. Preserve the existing younger-user policy dependency instead of inventing a deficit rule. These features remain in scope while recognition develops.

### 5. Add the polished original coach after interaction validation

Use `research/boxmaxxing/coach-animation-and-camera-design.md`. Prototype target placement first; prepare an original character/rig/animation production brief in parallel. A proposed jab/cross starter library is roughly12–16 short clips, subject to artist review. Full-size demonstrations; restrained/translucent coach and clear pads during full-screen-camera training. Validate what actually obscures the user before committing to the arrangement.

The coach is a reusable animated 3D rig, not an LLM-generated animation per round. Keep render-ready markers and exercise state synchronized. Missing art/model files are explicit dependencies, not permission to ship extracted competitor assets.

### 6. Release readiness

Finish the app-owned Qwen gateway, developer-configured food catalog integration, verified StoreKit access rules, privacy/data controls, accessibility and sustained device testing. Purchases remain disabled during development. Verify real-device latency/thermal behavior, interruption recovery, data persistence/deletion and failures/offline behavior. Record the tested build and evidence.

## Working contract

Use SwiftUI Expert/Specialist, UI Patterns, Liquid Glass and microinteraction skills when relevant to actual UI work. Use Product Design for a requested visual/design pass; do not redesign the approved app as a side effect. Libraries.dev supplies React web packages and must not be installed into native SwiftUI; achieve any suitable effect natively. Use REA for additional shipped-artifact gaps, reusing existing evidence rather than repeating extraction; ordinary BOX source work uses normal tools.

Keep BUILD_STATUS.md and FEATURE_CHECKLIST.md current after each concrete increment. Distinguish implemented, actually tested, placeholder and externally blocked. Continue independent work while credentials, footage or art are unavailable. Ask concise questions only when a real choice/dependency prevents the next action. Do not claim work was verified in this planning pass merely because an earlier status file reports tests.

## Research entry points

- `research/baller/nutrition-workouts-adaptation.md`: existing food/target/catalog-plan findings. Baller uses hosted food estimates but much of its plan/workout composition is local catalog logic; do not misdescribe every feature as LLM-generated.
- `research/boxmaxxing/README.md`: feature overview.
- `research/boxmaxxing/sparring-analysis.md`: pad coach, judge, timing and reconstruction lessons.
- `research/boxmaxxing/classifier-analysis.md`: learned coordinate-sequence classifier and its limits.
- `research/boxmaxxing/coach-animation-and-camera-design.md`: original coach/overlay proposal.

No app implementation changed in preparing this brief.
