# Complete BOX feature checklist

Updated 23 October 2026. Development order: personalized plans, executable training and nutrition first; live pad training/recognition follows. Latest user nutrition instruction removes the separate review launch gate; AI estimates remain unverified nutritionally. BUILD_HANDOFF.md plus the user's latest instructions govern scope. iPhone first; preserve the approved charcoal/red photo-free UI. All durable user records use local SwiftData; media uses protected local files indexed by SwiftData. Qwen is the developer-configured cloud AI layer. Only virtual sparring is deferred.

Legend: **Implemented** means connected code exists; **Tested** names actual evidence; **Placeholder** means no working flow; **Blocked** names the missing external dependency. An implemented flow is not automatically device-tested. This checklist is updated at each verified increment.

| Area | Required feature / acceptance | Current state | Remaining evidence/dependency |
|---|---|---|---|
| Device | Signed install and launch on Husein's iPhone | Recognition engine Debug/Release tests passed; latest validation-screen build installed; user confirmed saved test clip plays upright | Physical tracking, audio and interruption QA remains |
| Storage | Local SwiftData preferences, practices, meals, water, targets, chat | Implemented with one-time legacy import and store recovery | Persistent reopen, legacy migration/reset tests passed |
| Storage | Recovery, export/import, scoped deletion, media cleanup | Save errors, comprehensive reset and record JSON export implemented; import placeholder | Record export covered by tests; restore/import and media deletion QA incomplete |
| Profile | Experience, stance, goals, equipment, space, days, duration | Editable local profile, stance and days implemented | Full editable onboarding and constraints |
| Today | Next assignment, week schedule, start/resume, clear completion | Structured current-day assignment, rest days, completion/partial state and shared start/resume implemented | Simulator recovery, partial recap and Progress save verified; physical QA pending |
| Plans | Weekly personalized plan, exact budget, rest/recovery, reschedule | AI-only structured week, start date, recovery, protected acceptance and remove/start implemented; legacy reschedule preserved | Structured reschedule needs whole-plan revalidation; physical QA pending |
| Plans | Qwen plan proposal validated against catalog, user accepts | Typed full-catalog draft/preview/regenerate/accept and local validation implemented | Live fictional-profile seven-day proposal/accept/save passed |
| Drills | Search/filter punches, defense, footwork, combinations, fundamentals | 30 original structured boxing/support activities implemented, all six basic punches included | Native search and all/foundation/camera or exercise-kind filters implemented; phone QA and coach review pending |
| Drills | Instructions, demonstrations, prescriptions, linked follow-up | Reusable setup/steps/cues/mistakes/prescriptions and guided practice implemented; no demonstrations claimed | Original media and coach review |
| Sessions | Preparation/work/rest/reset, voice, pause/skip/end, truthful recap | Implemented; timer unit tests and simulator interactions tested | Device audio/interruption testing |
| Sessions | Bag/pads/shadowboxing settings and workout-specific prescriptions | Implemented manual shadowboxing/bag/pad variants with equipment/space checks and shared timed/rep player | Live camera pad training remains next phase, unavailable |
| Workouts | Strength, conditioning, core, mobility, skipping, running | Six guided presets and preserved manual logs implemented through shared timed/set player | Coach review and physical session QA |
| Workouts | Generate/modify, review/save, resume, history | Preserved checklist drafts; guided presets/collections and AI preview/accept implemented | Offline eligibility/budget/recovery tests pass; workout-specific live response QA pending |
| Nutrition | Meal add/edit/delete, date history, calories/protein/carbs/fat totals | Implemented manual add/edit/delete and date totals | Persistence, edit/delete and DST tests passed; meal entry observed in simulator |
| Nutrition | Editable calorie/macro/hydration targets | Manual and accepted AI targets implemented | Numeric checks/persistence tested; no clinical review claimed |
| Nutrition | Target generation from profile with editable explanation | AI-only generation, explanation, editable preview, local checks and explicit acceptance implemented | Live fictional-adult response/acceptance passed; individual dietary suitability unverified |
| Nutrition | Text/photo estimates, serving/assumptions, edit before log | Typed text/photo estimate and editable review implemented; neutral source labels | Food/photo-specific live tests pending; configuration is present |
| Nutrition | Barcode/product/serving lookup and missing-data handling | Typed barcode/catalog client and serving review implemented; network blocked | Contact deliberately unset; live scanner unbuilt |
| Water | Add custom/quick amount, daily target/history, delete correction | Implemented quick/custom entries and delete correction | Persistence and DST day-boundary tests passed; quick entry observed |
| Progress | Actual practices, work duration, rounds/cues, saved history | Detailed completed/partial/skipped/unstarted session records and legacy history implemented | Persistence tests and simulator partial-save/history verified |
| Progress | Consistency, week trends, assessments, comparisons, personal bests | Active-day counts/streak implemented; assessments/trends incomplete | Ability requires validated recognition |
| Rewards | Honest activity streaks/challenges/milestones/badges | Placeholder | Durable completions; no recognition points until supported |
| Calendar | Planned sessions, gym/sparring logs, optional bout dates/reminders | Seven-day accepted assignment list, rest days and weekday preference implemented | Gym/sparring/bout event model and reminders unbuilt |
| Camera | Permission, live preview, local clip recording, lifecycle cleanup | Implemented; physical recording/playback confirmed with rotation defect corrected and fresh-clip playback confirmed | Physical camera/thermal/lifecycle tests |
| Recognition | Labelled consented clips including idle/other/occluded | Camera test label/record UI implemented; no reviewed labelled corpus | Physical UI/recording QA and reviewed action/onset labels needed |
| Recognition | Authorized original models and exact feature/classifier contract | Original Thunder/Lightning + 19,369 recovered parameters; Swift classifier/features/tracker and complete local reference kernel implemented | Numerical/pixel/reference checks pass; direct-Swift port of remaining state machines incomplete; no fresh-training prerequisite |
| Recognition | Labelled accuracy and real-device latency/thermal behavior | 150 live frames per build tested on iPhone17: Release capture→result median 60.75 ms / p95 67.75 ms; nominal thermal state | No labelled accuracy/false-positive results, sustained thermal or same-video pose-parity evidence yet |
| Reaction coach | Recognize response, timing/counts, uncertainty and feedback | Full source recognition reference running; Swift judge primitives and StepJudge reference pass fixtures; validation UI unscored | Assisted Learn/Live Pads/shared-session adapter, visible-cue clock and labelled validation remain unfinished |
| Reaction coach | Supported corrections, points, adaptive pace/complexity | Selectable beginner/intermediate/advanced guidance and pacing implemented; technique grading, adaptive pace and points unavailable | Physical teaching/recognition validation and separate technique evidence |
| Review | Import/record shadowboxing, bag, pads and real-sparring clips | Local camera/import library/player/metadata implemented | User confirmed physical record/save/playback; 90° rotation defect corrected; fresh clip confirmed upright |
| Review | Timestamped observations, corrections, linked drills, edit/delete | Manual annotations and selected-frame request/report/save implemented; linked drills use shared catalog/player | Live evidence-grounded review tests pending; no recognition implied |
| Coach | Persistent chat, context, retry/cancel, clear errors | Persistent chat, disclosed context, retry/cancel/errors implemented | Chat-specific live responses not tested this increment |
| Coach | Explicit preview/accept for structured plan/target changes | Dedicated training/nutrition proposal screens with explicit acceptance implemented | Chat-driven transactional edits remain unbuilt |
| Account | Local profile, privacy/export/delete, no account needed offline | Local profile, reset and record JSON export implemented | Import/restore and privacy UI audit |
| Account | Login/identity | Local profile with no login selected by user; no account backend assumed | Local reset/export implemented; restore pending |
| Subscription | StoreKit products, purchase, restore, verified entitlement | StoreKit client/UI implemented; products unset and purchase testing blocked | App Store Connect products/agreements/IDs and sandbox account |
| Subscription | Access rules, manage subscription, offline grace | All features free during development by user decision; purchases disabled | Production policy/disclosures and StoreKit validation before release |
| Quality | Dynamic Type, VoiceOver, reduce motion, dark UI, performance | Unified native headers/cards/rows, simplified tab flows, search, glass utility controls, motion/accessibility fallbacks and haptics implemented | 23 Oct generic-iOS compile passed after one view-complexity repair; current visual/haptic/accessibility/performance QA awaits iPhone review |
| Deferred | On-screen virtual sparring opponent | Deferred by user | Separate future scope |

## External dependencies without blocking offline work

- Debug AI configuration is present; live training and nutrition targets were tested with fictional profiles. Customers never enter provider keys. Release builds need an app-owned gateway because embedded shared secrets are extractable.
- Training/evaluation footage with commercial rights, consent and reviewed labels; coach review of content/technique labels.
- App Store Connect subscription configuration and production access policy and local restore/backup decisions.

Baller source research: research/baller/nutrition-workouts-adaptation.md. Local catalog assembly is distinct from AI; no Baller code, content, media or secrets are shipped.


## Foundation increments verified on 20 October

1. **Catalog/contracts + UI:** 30 original activities; bounded prescriptions; explicit capabilities; neutral secondary style and provider-neutral copy. No maroon capsules or local personalized-plan generator.
2. **Executable player:** shared instructions/timers/sets/reps/rest/check-ins/recovery/recap across drills, prescriptions and workouts. Old checkpoints/records preserved with additive migration. Timer/check-in records are never camera-verified.
3. **Personalized plan/daily loop:** filtered-catalog AI generation, local validation/correction, preview/regenerate/accept, no silent overwrite; Today → assignment → player → recap → Progress. Live proposal/acceptance/persistence passed, including the corrected local-date context.
4. **Nutrition planning:** AI-only targets, editable preview, local arithmetic/purpose checks, explicit acceptance and Fuel connection. Live adult proposal/acceptance passed; no clinical review or dietary accuracy claim. User removed the separate reviewed-policy gate.

**Evidence:** 33 offline checks pass; 2 live checks are opt-in and were run separately. Simulator pause/kill/relaunch/partial check-in/save/history verified. That earlier foundation installation was interrupted; the current combined build has since installed and passed native recognition tests. Full physical UI/audio/long-session QA and scored Live Pads integration remain outstanding.

## Authorized recognition reference increment

See `research/boxmaxxing/port/README.md` for source-to-native map, exact artifact hashes/mode, commands and remaining boundaries. 62 offline checks pass / 2 live AI checks skipped; 3 native iPhone tests passed (both pose models, full synthetic kernel replay and 150 live camera frames). 72 original-ARM64 pixel vectors, 6 classifier vectors, 20 tracker frames, 7 feature vectors/5 windows, 271 timing/target boundary cases and 9 response-state sequences are regression evidence only. No labelled human-motion accuracy or technique-quality result is claimed.

Train → Camera test is a full-screen **validation tool**, not a competing training player. Labels and clips use existing local media/SwiftData storage; frames/detections remain transient. New UI builds/launches in simulator, including honest no-camera state. The user confirmed a recorded test clip saves and plays upright in Review; tracking/detection and interruption QA remain. Scores, camera-verified completion and AI live-pad assignments stay unavailable. The prior independent-model-training prerequisite is superseded by explicit authorization to reuse BoxMaxxing's model/code.

Typed native response bridge is implemented and host-tested: unique render acknowledgement, generation/capture ordering, pre-pause action rejection and uncertain-clock suspension. A real pad renderer and shared-session/result integration remain unbuilt; no camera-verified credit is available. Disabled primary controls use neutral charcoal app-wide. Latest camera-test UI is installed on iPhone, with record/save/upright playback confirmed by the user; tracking/detection QA remains.

## Camera integration — 21 October

Train → camera setup → Learn/Live rounds and supported jab/cross drill → camera practice are connected. Beginner aim guides/instructions and slower timing differ from Intermediate/Advanced; level remains user-adjustable. Shared session identity, save-once, paused recovery and Progress payload implemented. Six new offline tests pass (68 offline / 70 discovered, two live AI checks skipped). Simulator setup/level controls observed; new physical camera training flow remains unverified. Existing unfinished simulator practice was preserved. No demonstration/3D coach, technique grades or automatic live-pad assignments are implied. See BUILD_STATUS.md for scope and evidence.

## Personalized assigned guided/camera loop — 21 October 2026

Latest user authorization supersedes blanket AI camera-planning restrictions above. Capability catalog v2 enables only jab, cross and alternating one-at-a-time jab/cross camera rounds. Weekly AI proposals use the shared activity/mode/difficulty/budget validation and existing review/acceptance. Accepted mixed sessions execute through one GuidedExecution/SessionController, embedding the current camera player per set. Per-block camera observations remain separate from guided check-ins. Full assignment saving, same-ID resume, duplicate/stale completion protection, remaining-work labels and post-save Progress/next-session navigation are implemented. Existing target/calibration/recognition behavior is preserved.

Configuration: existing developer AI connection; production gateway remains a dependency. New behavior awaits physical-iPhone manual testing. The single generic-iOS Debug compile passed; no repair/recheck was needed. No tests, simulator launch/screenshots, phone installation/launch or live AI requests were performed. Historical automated test evidence is not a new pass. See BUILD_STATUS.md for the five-item phone checklist and compile result.

## Interface unification — 23 October 2026

**Implemented:** current Today composition retained; Train/Review/Fuel/Progress and detail flows share charcoal/red components, neutral secondary controls and a clearer action hierarchy. Repeated feature banners are removed; feature explanations are expandable, while safety, consent, failures and uncertainty stay accessible. Drill/exercise search and filters are connected. Camera diagnostics moved to Settings → Advanced; recording remains in Review. Progress history opens actual saved recaps. Native glass is limited to floating controls/navigation, with opaque fallbacks; press/selection/success haptics and reduced-motion-aware transitions are connected.

**Tested:** generic-device Debug compile passed after fixing one oversized SwiftUI expression. No current screenshots or runtime/device QA were obtained, and no tests, simulator or phone automation were run. **Awaiting phone review:** all tab/detail flows, back navigation, food/target menus, guided/camera entry, chat keyboard layout, Dynamic Type/VoiceOver, glass fallbacks and haptic feel. **Preserved:** SwiftData records/schema, plan/assignment execution and camera algorithms/target fixes. **Dependencies:** unchanged AI production gateway, barcode contact, nutrition/content review and recognition validation boundaries. No new fixtures, scores or placeholders were presented as working features. See BUILD_STATUS.md and design/UI_REFRESH.md.
