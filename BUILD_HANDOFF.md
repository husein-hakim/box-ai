# Boxing app — start here

## Latest steering — 23 October 2026

Unify the native UI around the approved Today screen and the supplied competitor references. Preserve the photo-free charcoal/red character and current functionality; simplify clutter, repeated banners and competing entry points. Use neutral rectangular secondary controls, restrained motion/haptics and native glass only where useful. The 23 October refresh is implemented and compile-checked; visual/accessibility/haptic QA awaits the user's iPhone. The prior no-simulator/one-compile verification limit was respected (one necessary compile-failure repair/recheck). See BUILD_STATUS.md, DESIGN_RULES.md and design/UI_REFRESH.md. Camera/target algorithms and durable data were not redesigned.

## Latest steering — 21 October 2026

Connect accepted personalized plans to the shared guided/camera executor and daily completion loop. The user explicitly authorizes AI scheduling of implemented camera jab/cross and Live Pad sessions now; the older blanket manual-accuracy planning gate is removed. Keep the explicit three-activity camera catalog, experimental measurement labels, current camera/target fixes, and guided fallback. Read the newest BUILD_STATUS.md section. Verification for this increment is one generic-device compile only; no simulator runs/tests/screenshots or phone automation.

## Latest steering — 20 October 2026

This section supersedes the older planning notes below. iPhone/native SwiftUI is confirmed. Preserve the approved photo-free charcoal/red interface across all screens; **never use maroon accent-tinted capsule buttons**. See DESIGN_RULES.md.

Complete personalized plans, executable guided training and nutrition planning before live pad training. The foundation is now implemented; read BUILD_STATUS.md and FEATURE_CHECKLIST.md for tested behavior and remaining dependencies. Guided drills/plans/workouts share the existing player/controller and preserve older SwiftData records/checkpoints. No local personalized training/calorie-plan generator or simulated recognition is allowed. All generated plans/targets use developer-configured Qwen, with typed proposals, local validation and explicit acceptance; provider names do not appear in product copy and customers never enter keys.

The user subsequently said “just let qwen do its thing” regarding nutrition. This removes the earlier separate clinical-policy review launch gate. Implement AI target estimates with numerical validation and review/acceptance; no clinician approval is claimed and weight cuts/deficits are unsupported. See NUTRITION_POLICY.md for actual safeguards and limits.

Next phase: full-screen-camera live pad training, genuine jab/cross recognition/feedback, then an original animated coach. Latest authorization: reuse BoxMaxxing's supplied models/code. This supersedes the independently trained replacement/architecture-comparison prerequisite. Port unchanged bundled MoveNet plus its exact temporal classifier and candidate/judge pipeline; validate with labelled data and iPhone measurements before enabling scores. See research/boxmaxxing/REUSE_PORT_PLAN.md and port/README.md. Tactical opponent/virtual sparring remains deferred. No original demonstration media exists. The authorized recognition reference now runs on iPhone; scored training/session integration and accuracy validation remain unfinished.


Updated 19 October 2026. This is the current handoff from the research/planning chat. It summarizes the user's approved direction and subsequent steering. It takes precedence over older product proposals where they differ. No production app or trained boxing model exists in this workspace yet.

## Product and communication

Build an original boxing training companion inspired by Baller AI's football product. The user likes a simple feature-by-feature comparison and short, concrete explanations. Avoid long strategy dumps, excessive caveats and repeatedly reopening settled product direction.

The headline feature is **live reaction coaching**: coach calls an action/combination → camera observes what the boxer actually does → recognition and supported technique assessment → immediate feedback/points → next callout. Pace and complexity should adapt to performance. This is the desired product, not demonstrated functionality.

**Virtual sparring with an on-screen opponent is deferred**, not required for the initial build. The user might revisit it if execution is compelling; do not make it a launch dependency. Recorded real-sparring footage review is a separate feature.

## Entire feature vision

| Feature | Boxing behavior | Baller relationship |
|---|---|---|
| Onboarding/profile | Experience, stance, goals, equipment, space, actual days and session duration | Adapt football onboarding |
| Personalized plan | Boxing skill sessions, bag work, conditioning and recovery | Similar breadth; make constraints meaningful |
| Today | Clear assignment and start/resume action | Daily companion pattern |
| Drill library | Punches, combinations, defense, footwork and fundamentals | Original boxing replacement for football curriculum |
| Guided sessions | Demonstrations, instructions, rounds/rests and spoken cues | Similar session structure |
| Live reaction coach | Recognize response to rapid callouts; feedback and points; supported corrections | Extends beyond Baller's recovered separate voice/pose features |
| Bag/pad sessions | Setting-specific technique, combinations and conditioning | Guided sport practice equivalent |
| Video review | Shadowboxing/bag/pad/real-sparring clips; timestamped observations, corrections, linked drills | Similar report loop, different vision requirements |
| Coach chat | Questions, explanations, contextual session changes | Contextual coach equivalent |
| Workouts | Strength, conditioning, core, mobility, skipping and running | Supporting training pillar |
| Nutrition | Editable food/macros/water; photo/barcode estimates in broader vision | Supporting Baller-style pillar |
| Daily challenges | Brief technique/footwork/conditioning goals | Habit loop |
| Progress | History, consistency, repeatable assessments and comparisons | Separate activity from ability |
| Rewards | Points, streaks, milestones, badges; leaderboard optional later | Gamification equivalent |
| Calendar | Weekly training, gym/sparring logs, optional bout dates | Schedule/season equivalent |
| Account/settings | Backup, reminders, subscription, privacy/deletion | Supporting app infrastructure |

Proposed navigation: Today / Train / Review / Fuel / Progress, with coach accessible contextually. This layout is a proposal, not a user-approved final visual design. iOS/Core ML has been the working technical direction; platform/framework/visual identity are not explicitly finalized by the user.

## AI mechanics: preserve these distinctions

Two candidate learned action recognizers were discussed:

1. **Pose-sequence model:** Apple Vision extracts joint positions per frame; a custom trained model classifies coordinate sequences into jab/cross/slip/etc.; Core ML runs it on-device. This is learned recognition, not hand-written wrist thresholds.
2. **Video-sequence model:** a custom model consumes RGB frames directly and learns appearance/motion; convert a compatible model to Core ML for deployment.

The user dislikes brittle movement rules and wants strong accuracy across practical camera setups. They initially favored direct video, then asked to understand pose-sequence learning and dataset availability. **No final architecture choice has been made.** Evaluate both on the same labelled footage, unseen people and recording setups. Do not interpret their clarification questions as approval of one approach.

Core ML is the on-device deployment framework, not an accuracy guarantee or a ready-made boxing recognizer. Apple pose alone does not recognize punches. Existing pose coordinates from another extractor are not automatically interchangeable with Apple Vision output.

Recognition (which action), event timing/counting, and technique assessment (whether it was performed correctly) are different tasks and need appropriate labels. Include idle, unrelated movements and uncertain visibility; never infer the action simply because it was requested. Deduct points for supported wrong responses, not camera uncertainty.

Keep live inference/cue timing local. Cloud models can support detailed review/chat, outside the immediate reaction loop. A previously discussed ~200ms feedback figure was a target after enough movement is observed, not an achieved latency. Measure action-observation delay separately from inference/audio delay. Do not invent detection, technique scores, force or real contact metrics.

## Data research — leads, not validated acquisitions

- **BoxingVI:** https://github.com/Bikudebug/BoxingVI ; paper https://arxiv.org/abs/2511.16524 . Authors describe 6,915 clips, six punch types, temporal labels and AlphaPose/COCO skeleton data; repository links a Drive download. Files have NOT been downloaded/validated and commercial terms have NOT been established. Re-extract coordinates with the intended production extractor when comparing methods.
- **BoxMAC:** https://arxiv.org/html/2412.18204v1 . User explicitly supplied this paper. 15 professional boxers, 13 labels, 60k+ frames, 2,314 clips; reported test results 73.9% best image baseline and 71.9% video baseline. This does not demonstrate mobile latency, technique scoring or camera-independent reliability. No working dataset/weight download established in our investigation.
- **UTD-MHAD:** https://personal.utdallas.edu/~kehtar/UTD-MHAD.html . Video/skeleton download links, but generic front-boxing label rather than detailed boxing vocabulary.
- NealBeans/BoxingDataset on Hugging Face was checked: visible repository files were metadata, and its card states noncommercial/academic use. Do not claim it provides ready-to-use commercially licensed video.

One consented video collection can train both approaches: retain labelled original clips and automatically derive pose sequences. Own phone-recorded examples, varied users/setups and coach-reviewed labels will be necessary for product evaluation. Public pro-fight datasets differ from solo phone-facing training. No training data/model has been acquired or trained here.

## Recovered Baller evidence

Target: /Users/husein/Downloads/Baller-1/base.apk plus splits, Android com.getballerai.app 1.1.3/code11. REA inventoried the archive; Android REA decompiler provider was unavailable, so isolated ordinary JADX and fallback instruction listings were used. Do not call ordinary decompilation REA Evidence or claim runtime verification.

Recovered: 170 bundled drills, 32 guided technical playlists, five physical workouts, eleven daily challenges; weekly plans and AI Practice use local catalog assembly. Callouts use speech/timers; local pose counters use numerical motion rules. Film samples 14 JPEGs from up to the first20 seconds and requests a vision-model coaching report. Actual production backend behavior, accuracy and commercial success were not established. No app was launched/private API used. Do not transplant their original code, assets or football copy.

## Files to read selectively

1. **This file first** for latest decisions.
2. `/Users/husein/Documents/box/research/baller/boxing-product-plan.md` — full product proposal; virtual-opponent launch prioritization is superseded by this handoff.
3. `/Users/husein/Documents/box/research/baller/boxing-planner-spec.md` — proposed content, filtering, timing, progression and tests.
4. `/Users/husein/Documents/box/research/baller/features-analysis.md` — source-backed Baller feature inventory.
5. `/Users/husein/Documents/box/research/baller/video-analysis.md` and `live-camera-analysis.md` — Baller's distinct vision paths.
6. `/Users/husein/Documents/box/research/baller/README.md` — evidence index and limitations.
7. `/Users/husein/Documents/box/research/baller/virtual-sparring-spec.md` — optional deferred design, not initial scope.

Detailed proposals contain editorial targets, schedules, pricing and evaluation thresholds that the assistant suggested. They are not all user-approved commitments. Dataset findings above are dated research leads; reverify access and terms when acquiring data.

## Suggested implementation start

Inspect the workspace and applicable instructions. Confirm only consequential missing choices, such as native iOS vs another platform, before dependent scaffolding. Then build incrementally: app shell → Today and shared round player → original sample drills/planning → reaction callouts/camera capture → isolated inference interface and feasibility evaluation → verified detector integration. Develop uploaded-video review separately. Supporting nutrition/progress/account flows follow the core path, without dropping them from the broader vision.

Use clearly labelled development fixtures for unbuilt inference and never present simulated scores as actual camera analysis. Do not reduce the headline feature to a timer and imply live coaching is complete. Maintain a short build status/decision log as implementation proceeds. Ask for API credentials or required services only when a concrete integration needs them. Keep research tooling and decompiled reference material outside shipped app sources.
