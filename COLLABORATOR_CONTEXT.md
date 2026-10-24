# BOX — complete collaborator context

Prepared 24 October 2026. Workspace: `/Users/husein/Documents/box`.

This is a product and engineering handoff for a collaborator joining the existing project. It combines current source inspection, project status and the owner's decisions and phone feedback. It is not a claim that every implemented feature has been tested end to end. No application code was changed to prepare this handoff.

## 1. Read this first

BOX is an original, native iPhone boxing companion. Its headline feature is live camera-based reaction/pad training, supported by personalised training plans, executable drills/workouts, nutrition tracking, video review and coach chat.

The app already exists. Continue from the implementation; do not scaffold another app, replace its approved design or rebuild working systems simply because an older planning document describes them as future work.

The owner, Husein, uses this chat for orchestration, research and prompts. Another coding chat, called “Sol,” implements changes. When Husein asks this orchestrator what to build, normally provide a clear implementation prompt instead of editing the product. A collaborator explicitly assigned implementation should carry it out.

### Current decisions that override older documents

- Native SwiftUI, iPhone first; deployment target iOS 18.0.
- Durable personal records stay in local SwiftData, without CloudKit. Video files stay in protected local storage indexed by SwiftData.
- Qwen is the developer-configured cloud AI layer. Customers do not supply API keys or see provider branding.
- Personalised training and nutrition proposals come from Qwen. Local code validates, executes, persists and calculates totals; it must not silently fabricate a personalised fallback plan.
- Camera sessions **are enabled for Qwen scheduling now**. The owner explicitly removed the earlier blanket gate requiring satisfactory phone tests before scheduling them.
- Recognition capabilities remain limited to actually supported actions. Enabling scheduling does not enable camera judging of every activity in the catalog.
- BoxMaxxing model/code reuse was explicitly authorised by the owner, who reports permission from its developer. An independent model-training project is not a prerequisite. Artwork, character models, animation, audio and private services are separate permission scopes.
- Live Pads is the intended current “sparring-like” experience. A tactical virtual opponent that attacks and requires defense/counters remains deferred.
- Instructional demonstration footage/animations are also deferred for now. Do not display fake demonstration players.
- All features are free during development. Login is not required. Subscription products/purchases remain unconfigured/disabled.
- Use the approved photo-free charcoal/red UI, native navigation and neutral rectangular secondary controls.
- For current implementation increments: **no simulator launch, simulator UI tests, simulator screenshots or simulated-camera testing**. The owner manually tests camera behaviour on a physical iPhone. Perform one compile check, repair compile errors and recheck only as necessary, then hand back a short phone checklist. Do not enter a broad testing loop or install/automate the phone without a new request.

## 2. Product purpose and user experience

The app should help users actually complete and track training, not just list exercises. Training covers punches/combinations, fundamentals, footwork, defense and physical preparation, with personalisation based on experience, goals, equipment, space and schedule.

The primary loop is:

**Today → assigned session → instructions → guided/camera blocks → recap → save → Progress and assignment updated → next activity.**

Two related camera experiences share the same recognizer:

1. Camera-assisted drill practice: learn or practise a supported movement with instructions, callouts and optional target accuracy.
2. Live Pad rounds: timed rounds of supported callouts, responses and rest.

A visible target is a calibrated 2D aiming region, not a physical pad. The phone is placed safely outside striking reach. Camera recognition must not be described as proof of correct technique, impact, power or real sparring ability.

### Five tabs

| Tab | Purpose |
|---|---|
| Today | Next assigned action, current schedule, resume and completion status |
| Train | Personalised plan, Live Pads, drill/exercise discovery and workouts |
| Review | Record/import/play footage, annotations and requested AI reports |
| Fuel | Food, calorie/macronutrient targets and totals, water |
| Progress | Actual completed/partial work, history and saved recaps |

Profile/settings and persistent coach chat are secondary destinations. Developer camera diagnostics live under Profile & settings → Advanced; ordinary recording/import belongs in Review.

## 3. What is implemented and what remains

“Implemented” below means connected code exists, not universal runtime verification.

| Area | Current implementation | Remaining boundaries |
|---|---|---|
| Profile | Local preferences, experience, stance, goals, equipment/space, available days/time | Fuller onboarding and physical UX review |
| Curriculum | 30 original structured activities; all six basic punches plus combinations, fundamentals, footwork, defense, strength, conditioning, core, mobility, warm-up/cooldown | Boxing-coach content review; no demo media |
| Guided execution | Ordered instructions, timed/rep sets, work/rest, voice, check-ins, pause/resume, skip/end, durable drafts and truthful partial recaps | Current phone audio/lifecycle/complete-flow QA |
| Workouts | Six guided presets, collections/proposals, manual workout logs/checklists | Live workout-specific AI output and physical execution QA |
| Weekly plans | Qwen structured seven-day proposals, catalog validation, correction/error path, preview/regenerate/accept, SwiftData assignments | Latest camera-enabled generation and whole daily loop need phone QA |
| Assigned camera sessions | Guided/camera selection for compatible blocks; mixed execution, per-set observations, identity and completion protection | End-to-end physical QA, including resume/fallback/save-once |
| Live Pads | Learn attempts and timed rounds, levels, stance, recognition, target accuracy/reaction mode, feedback and saved measurements | Accuracy/false positives across people/devices and longer-session performance |
| Food | Manual add/edit/delete, day history, calorie/protein/carbohydrate/fat sums; typed text/photo estimation and editable review | Food-specific live accuracy/response QA |
| Nutrition planning | AI targets/energy estimate/explanations, editable preview, numeric checks and acceptance | Nutritional suitability unverified; no clinical-review claim |
| Water | Quick/custom entries, daily target/history and correction by deletion | Current phone UX QA |
| Barcode | Product lookup/serving contracts and review UI | Developer public contact deliberately unset; live scanner unbuilt |
| Video | Local record/import/playback, notes, manual timestamped annotations, selected-frame AI request/report/save, drill links | Live evidence-grounded report quality QA |
| Coach | Persistent contextual chat, errors/retry/cancellation | Chat-specific live QA; transactional plan changes from chat unbuilt |
| Progress | History, detailed practice recaps, complete/partial distinction, active-day/streak information | Richer trends/assessments/personal bests and rewards unfinished |
| Data control | Local save/recovery, legacy migration, JSON record export and reset | Restore/import and full backup/media deletion QA unfinished |
| Subscriptions | StoreKit scaffolding/UI | Products, agreements, entitlement QA and production access policy; purchases disabled |
| Tactical opponent | Deferred | No attacking opponent/defense-counter game claimed |
| Teaching animations | Deferred | No reviewed footage, original animation library or shipped 3D coach |

## 4. Personalised planning and execution

### Qwen training contract

The generator receives compatible catalog/capability data, experience, stance, goals, equipment/space, availability, local dates/timezone, duration and source-aware recent completion/feedback. It returns a typed week with session types, ordered stable activity IDs, difficulty, sets/reps or work/rest and rationale.

Local validation checks valid IDs/modes, profile constraints, equipment/space, difficulty, numerical bounds, schedule coverage, time budget including programmed rest, warm-up/cooldown and recovery spacing. There is one correction attempt using actual errors; invalid results must not be saved as accepted plans. The user previews and explicitly accepts. Stale contexts and overlapping accepted/completed dates are protected.

Camera capability catalog v2 advertises only:

- `jab-reset-v1`
- `cross-reset-v1`
- `jab-cross-reset-v1`

The last one alternates single cued jabs/crosses with resets. It is **not continuous combination recognition**. Other punches, footwork and defense can appear as guided/manual activities without camera verification.

### Assignment execution

Today and Your plan launch the entire accepted session in order. Compatible blocks can use guided or camera execution; bag/physical-pad work must not silently turn into shadowboxing. The enclosing guided executor owns inter-set rest, remaining blocks and the final assignment recap. A camera set completing must not complete the whole mixed workout.

Persist assignment ID, immutable block IDs, set position, mode/stance, camera state and earlier observations in the draft. Resume reuses that session; camera recalibrates. Time away earns no work credit. Continue-guided fallback preserves prior observations and elapsed work while requiring honest manual confirmation for the remaining activity.

Only final saving writes whole-session history and completion. Shortened/skipped work is partial; save-once protections prevent duplicate history/credit. Accepted plans and execution work offline after generation. Structured whole-plan rescheduling is not generally offered because recovery constraints need revalidation.

### Nutrition

Qwen proposes fueling targets, estimated energy need and explanations. The app validates finite bounded values, age/purpose, no deficit relative to the model's own energy estimate and macro-energy consistency within 5% using 4/4/9. These checks do not establish nutritional correctness. No weight-cut/deficit goal or clinical approval is claimed. Younger-user handling and a `needsSupport` outcome exist; consult `NUTRITION_POLICY.md` before changing policy.

Manual targets/food edits remain available. AI estimates retain their source/assumptions and do not become verified nutrition when saved.

## 5. Camera and recognition: how it actually works

### Shared recognition pipeline

AVFoundation capture → orientation/full-source preprocessing → original MoveNet TFLite pose graph → tracked/normalised movement features and temporal classifier → recovered candidate/judge state machines → cue-specific result → UI feedback and local recap.

- Bundled original MoveNet Thunder and Lightning graphs; TensorFlowLiteC 2.17.0 CPU/XNNPACK. This is not an Apple Vision pose pipeline.
- Recovered classifier: 19,369 parameters and a 24×85 temporal feature input; native Swift classifier/features/tracker/judge primitives.
- Remaining recovered coaching state machines execute through a restricted JavaScriptCore interpreter: 332 original functions. Do not describe this as a complete direct-Swift rewrite.
- Action detection is local; Qwen is not in the live reaction loop.
- Current supported recognition exposed to users is straight lead/rear punching. Other recovered outputs and classifier labels do not establish supported technique grading.
- Renderer acknowledgements, cue IDs, capture order, camera generation and onset boundaries prevent stale/pre-pause results from counting. Acknowledgement means renderer submission, not a measured photon presentation timestamp.
- Every-frame data is transient. Ordinary training does not upload or persist camera frames. Explicit Review/diagnostic recording is a separate path.

### What earlier phone problems taught us

Originally the app cancelled on single bad frames, used a nominal upper-body presence gate that required hips, could crop extended arms, and treated uncertain punch judgments as body loss. These were confirmed implementation issues, not proof MoveNet itself was the root cause of every failure.

Latest fixes use explicit upper-body framing/full camera view, bounded gap handling that stops unreliable scoring while preserving a cue where appropriate, and separate body, calibration, processing-delay and judgment explanations. Sustained loss pauses/retries without fabricated misses. Follow source and newest status sections for exact timing thresholds; do not blindly loosen classifier thresholds.

User-facing explanations should be actionable when evidence supports them: move closer/farther, keep shoulders/arms in view, hold guard to calibrate, or processing delayed. Never tell someone to move when the actual problem is latency.

### Target accuracy and coordinate mapping

The old dot was a shoulder/nose-derived visual guide independent of scoring. Screen clamps and independent preview rotation could move its apparent position. The owner reported hits inside the dot failing while hits above it counted.

Current `Core/PadTargeting.swift` supplies shared upright-source, aspect-fit, front-mirrored geometry for preview/overlays, targets and geometric judging. No hidden aspect-fill crop or decorative screen clamping should change the target's position.

Target-accuracy setup measures guard and comfortable lead/rear projected reach for the requested hands. The endpoint is relative to shoulder centre, shoulder axis and apparent scale. It needs observable 2D travel; a slightly angled view can help, with both shoulders/arms visible. Head/nose, shoulders, elbows and wrists are relevant; hips/knees/feet are not required for jab/cross mode.

Targets adapt between cues to stable body position/scale and freeze during each cue. Meaningful scale/orientation changes, camera changes and pause/resume require recalibration. A target that cannot fit should prompt reframing, never silently relocate.

A real accepted punch is required before evaluating target reach. A bounded reliable wrist path near its extension peak is checked against the same displayed region. Ring crossing alone does not count as a punch. Missing geometry/peak coverage yields unclear aiming and a retry, not an invented hit/miss.

Keep these outcomes distinct:

- Recognised punch, target reached.
- Recognised punch, target missed, with measured directional guidance if possible.
- Recognised punch, aim unclear, retry.
- Wrong hand/kind, early response or timeout.
- Actual tracking loss or processing interruption.

Reaction-only mode uses recognition/timing without an aiming dot. Neither mode measures contact, depth, power or certified technique. AR depth sensing is not currently required or implemented for this target system.

### Experience levels

User-adjustable Beginner/Intermediate/Advanced change target guidance, reminders and pacing, not the truthfulness of recognition. Existing response/reset defaults are 6/2.5 seconds, 3/1.5 seconds and 1.8/1 seconds respectively. These are product defaults, not validated skill benchmarks. Beginner guidance should make hand/target/reset understandable; advanced users can keep help enabled.

## 6. Latest physical feedback and verification limits

The owner's first shared beginner recap showed 7/8 responses recognised, one timeout, 17 tracking interruptions and 722 ms median onset. They reported poor readiness visibility and inconsistent success feedback.

After tracking and target fixes, on 23 October they said the experience was “a lot better.” Their screenshot showed:

- 8 completed attempts.
- 7/8 responses recognised.
- 7 2D targets reached.
- 0 recognised target misses.
- 0 recognised aim-unclear retries.
- 3 unclear cues retried.
- 977 ms median response onset.

This is one user-reported session and an app-generated recap, not independently labelled accuracy evidence. The old interruption counter and new unclear-cue counter are different metrics; do not claim an apples-to-apples reduction. The onset medians are not model inference latency and do not prove improvement/regression in speed.

Historical evidence includes 68 offline checks passing/70 discovered with two opt-in AI checks skipped, earlier numerical/pixel/kernel parity fixtures and short real-device engine runs. A Release iPhone 17 engine run measured capture-to-result median 60.75 ms/p95 67.75 ms over about eight seconds. This is historical, short-duration evidence, not current sustained performance or human-motion accuracy.

The 21 October mixed-plan increment and 23 October UI pass passed generic-iOS Debug compilation. They were not fully retested on simulator/device; historical test counts do not validate later changes. Current task only inspected files and created this document; no new build or tests were run.

## 7. UI and presentation rules

The 23 October pass unified Train, Fuel, Review, Progress and detail flows while preserving Today. Use `DESIGN_RULES.md` and `design/UI_REFRESH.md`.

- Solid charcoal content panels, warm white type, restrained red primary actions, native typography/SF Symbols and generous spacing.
- Neutral rectangular secondary controls, subtle borders, 12-point corners; no maroon secondary capsules.
- One focal action per screen; compact secondary tools, search/filter libraries and expandable detail.
- Native glass only on appropriate floating/navigation utilities; opaque Reduce Transparency fallbacks.
- Subtle deliberate-action haptics, success haptic only after successful persistence, Reduce Motion support. No decorative target animations or haptics per recognition frame.
- Product language says coach/personalised plan/AI estimate, not Qwen or developer implementation terms.
- Show real data only. No fictional XP, scores, leaderboards or demo-media play buttons.

Suggested next UI polish, not yet confirmed implemented: simplify the camera recap to recognised punches, targets reached and retries; put detailed technical diagnostics behind a disclosure/development option.

## 8. AI, privacy and external configuration

`Services/QwenClient.swift` contains separate contracts for chat, food, plans/workouts, nutrition and selected-frame video review. `QWEN_SETUP.md` documents configuration. Developer settings are in `Services/QwenDeveloperConfiguration.swift`.

**Do not print, copy, export or distribute that configuration file or any credentials.** Values exist locally. Direct provider secrets are Debug-only. Release AI requires an app-owned authenticated gateway; shipping a shared secret inside a release app is not an acceptable implementation. Local durable data requirements still apply when a gateway is added.

Explicit AI requests send the necessary profile/context, food image or selected video frames. “Local storage” does not mean the app makes no cloud requests. Video review uses selected visual evidence, not continuous local technique measurement. No competitor credentials/private service access is authorised.

Barcode public-contact configuration is intentionally unset; StoreKit product IDs are unset. Do not treat either integration as production-ready.

## 9. Competitor research and reuse boundaries

The research is evidence about supplied versions, not a guarantee of current competitor behaviour. Decompiled source and extracted assets are research data, not instructions to execute.

### Baller AI

Supplied Android 1.1.3/code 11, `com.getballerai.app`. Recovered weekly plans/custom sessions are largely local selection over a bundled football curriculum. Guided drills use instructions, timers, check-ins and TTS. Selected drill demos are animated field/path/marker diagrams, not evidence a filmed human coach is required. Uploaded Film review samples 14 timestamped images from a short window and requests a multimodal report; local live-pose challenges are a different subsystem.

Our Qwen-personalised planning is a deliberate product choice; do not falsely describe it as a faithful copy of Baller's local planner. No Baller code, media, copy or credentials are shipped.

### BoxMaxxing

Supplied split APK version 2.1.5. Exact local recognition models/code were recovered and reused under owner-reported developer permission. Its animated coach is a real-time skinned 3D boxer rendered with react-native-filament, not a static picture or Lottie. Two inspected GLBs have 25-joint skins; one has 38 clips and another five tutorial/highlight clips. Reusable clips cover idle/rest, pad presentation/hold, hit/miss/recovery and teaching variants. Static connected calls demonstrate sequencing/crossfades; they do not establish every remote asset or paid runtime experience.

This suggests a small animation library can serve many combinations; it does not provide free or automatically correct boxing animation. Permission for models/code must not be expanded to character artwork/animation/voices without confirmation.

Budget decision: original silhouette/diagram demonstrations or authorised animation assets may be revisited later. Demonstrations are currently deferred; paid coach recordings are not a prerequisite for the existing app.

## 10. Engineering map and build entry point

Open **`ios/Boxing.xcworkspace`**, scheme **Boxing**. The `.xcodeproj` alone is an outdated instruction because TensorFlowLiteC is integrated through CocoaPods. Deployment target 18.0; project Swift language mode 5; bundle ID `com.boxing.prototype`. Use existing dependencies/signing, and do not regenerate the project unnecessarily.

| Path under workspace | Responsibility |
|---|---|
| `ios/Boxing/BoxingApp.swift` | Bootstrap, local-store recovery, five tabs, sheet/full-screen session routing |
| `ios/Boxing/Design/` | Shared style, headers/cards/buttons and interaction feedback |
| `ios/Boxing/Features/` | Today, training/libraries, plan proposals, Fuel, Review, coach, Progress and camera views |
| `ios/Boxing/Models/AppStore.swift` | Observable app/store state, records and persistence coordination |
| `ios/Boxing/Models/LocalModels.swift` | SwiftData entities, food/water/chat/video and related records |
| `ios/Boxing/Models/PersonalizedPlan.swift` | Context, typed week proposal, validation and accepted-plan persistence |
| `ios/Boxing/Models/GuidedStore.swift` | Assignment launch, progress, guided/camera checkpoints |
| `ios/Boxing/Models/NutritionPlanning.swift` | Nutrition inputs, proposal checks and acceptance |
| `ios/Boxing/Core/ActivityCatalog.swift` | Original stable-ID curriculum/contracts |
| `ios/Boxing/Core/CameraPlanningCapability.swift` | Exact activities/modes advertised for camera planning |
| `ios/Boxing/Core/GuidedExecution.swift` | Shared block/set execution, including embedded camera sets |
| `ios/Boxing/Core/RoundTimeline.swift` | Legacy/custom round timing |
| `ios/Boxing/Core/PadTraining.swift` | Camera configuration, levels, cue/result/retry state and diagnostics |
| `ios/Boxing/Core/PadTargeting.swift` | Shared mapping, calibrated reach and target geometry |
| `ios/Boxing/Session/` | SessionController/Player, speech, execution routing and recap lifecycle |
| `ios/Boxing/Camera/` | AVFoundation capture and recording |
| `ios/Boxing/Recognition/Camera/` | MoveNet runtime, frame adapter/preprocessing and recognition worker |
| `ios/Boxing/Core/Recognition/` | Classifier/features/tracker/judge and restricted reference-kernel boundary |
| `ios/Boxing/Recognition/Resources/` | Bundled recognition model/reference resources |
| `ios/Boxing/Services/` | AI, video frame sampling, barcode lookup and StoreKit |
| `Tests/BoxingCoreTests/` | Existing domain, persistence, planning, targeting and recognition regressions |
| `Tests/RecognitionRuntimeTests/` | Native runtime validation tools/tests |
| `Package.swift` | macOS-hosted core test package; distinct from the iOS app target |
| `ios/Podfile`, `ios/Podfile.lock` | TensorFlowLiteC 2.17.0 dependency |

Preserve older records/checkpoints through additive optional payloads. Never reset user data to simplify development. Export includes records/provenance, not video bytes; restore/import remains unbuilt. Full-session completion and child camera results have distinct contracts.

## 11. Recommended immediate work

1. Manually verify a real Qwen week: generate → preview → accept → Today assignment.
2. Complete a mixed guided/camera session, save and confirm assignment/progress consistency. Verify a camera set returns to the remaining workout.
3. Check pause/relaunch/resume, continue-guided fallback and duplicate-save protection.
4. Collect specific camera issues from actual phone feedback; use local diagnostics rather than speculative model replacement or uncontrolled threshold changes.
5. Simplify recap presentation without losing saved detail.
6. Later: teaching assets, richer video-review/coach workflows, production AI gateway, barcode/subscription configuration and release preparation.

Do not repeatedly postpone the entire product for new-model training, but do not turn one successful phone session into validated technique/accuracy claims. No tactical sparring opponent or demonstration-media project is authorised merely by this roadmap.

## 12. Source documents and precedence

- `BUILD_STATUS.md`: latest dated implementation sections and evidence. Older sections are historical and sometimes contradict newer ones.
- `FEATURE_CHECKLIST.md`: broad scope; appended recent increments supersede stale table rows.
- `DESIGN_RULES.md`, `design/UI_REFRESH.md`: approved interface rules.
- `QWEN_SETUP.md`, `NUTRITION_POLICY.md`: configuration and current nutrition constraints. Do not bundle secrets.
- `research/boxmaxxing/port/README.md`: exact recognition artifacts, hashes, port map and evidence boundaries.
- `research/boxmaxxing/coach-animation-and-camera-design.md`: coach/animation investigation; retained REA parent `ev_01c2a52c11183d873f4829adc582d0cd62faca7c73b5f9f5c7e465c08a297852`, exported in its evidence folder.
- `research/boxmaxxing/README.md`: wider feature/research index.
- `research/baller/README.md`: Baller research index; feature/plans/video/live-camera reports link to decompiled evidence.
- `BUILD_HANDOFF.md`, `NEXT_BUILD_BRIEF.md`, `LIVE_PAD_PLACEMENT.md`, `README.md`: useful earlier context, but stale details must not override current source/latest owner decisions.

Specific stale claims to ignore: “no third-party dependency,” “open only xcodeproj,” “all results are timer/manual,” “camera integration unbuilt,” and “AI camera assignments disabled until phone validation.” Current workspace/source and newest status sections supersede these.

For a collaborator without this workspace, share this file plus the relevant original app source, dependency manifests and non-secret docs through an agreed private channel. Exclude developer secrets, user databases/recordings, build products and competitor extracted assets unless required and authorised. Absolute paths in this document are local navigation hints and need adapting on another machine.
