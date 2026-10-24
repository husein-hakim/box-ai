# Live Pad Training: placement and first build boundary

20 October 2026. Proposed placement instructions for Sol, grounded in current BOX source and retained BoxMaxxing evidence. This document specifies the next feature; it does not claim new implementation.

## Placement decision

**Primary home: Train, in the existing top Reaction Coach card.** Evolve that card into Live Pad Training. Keep Today / Train / Review / Fuel / Progress as the five tabs. Do not create a Sparring tab or hide live training inside the recording tool.

Preserve ordinary guided-audio sessions as a clearly named secondary option. The current Reaction Coach card starts an audio-only builder; do not merely rename that action and imply it performs camera recognition.

### Exact flow

**Train → Live Pad Training card → session briefing/setup → camera calibration → live rounds/rest → recap → saved Progress entry.**

- Card: title Live Pad Training; concise jab/cross description; primary Set up training action. Preserve approved visual style.
- Briefing/setup: initial jab/cross curriculum, stance, round/rest budget, camera requirement and clear capability state. Camera permission/framing/calibration comes before Begin. Ordinary guided audio remains available without camera.
- Player: full-screen camera with stable original pad targets/callouts; hide normal tab navigation during training. Reuse applicable existing timer, pause/resume, interruption and save/checkpoint logic. A dedicated camera presentation can use the shared session lifecycle without forcing camera state into every existing view.
- Recap: actual completed work and, only when recognition is validated/enabled, supported action/timing metrics. State insufficient tracking separately. Exactly one saved result per session; cancel/setup abandonment does not complete an assignment.
- Progress: one result with session type and originating assignment/drill when applicable. Selecting the result opens its recap/detail. A recording is optional and separate from a measured result.
- Review: local recordings and footage analysis remain here. Do not require users to visit Review to start live training.

### Secondary entry points

**Today:** keep the main card as today's actual assigned session. When an assignment is explicitly a Live Pad session, show that mode and launch the same briefing/player with the assignment context. Completing it updates that assignment and Progress. Do not replace every daily workout with pad training or fabricate a pad assignment on a rest day. An optional Practice pads shortcut can lead to the same standalone setup.

**Drill details:** add Practise live only for drills supported by the recognizer/session engine. A supported jab/cross drill opens the same flow with that drill selected. Do not add camera-scoring promises to footwork/defense drills merely because those instructions exist.

Both entry points reuse the Train-owned feature flow; they must not create separately maintained pad players.

## Existing training loop: partial, not absent

Inspected source:

- `ios/Boxing/Features/TodayView.swift`: resolves today's assignment and starts the existing session; resume checkpoint action exists.
- `ios/Boxing/Features/TrainingViews.swift`: Reaction Coach → builder, weekly plan/workout tools, separate Camera practice recorder and two instructional sample drills. Drill detail currently has instructions but no connected practice-launch action.
- `ios/Boxing/Session/SessionPlayer.swift`: briefing, prepare/work/rest/reset, spoken cues, pause/end, recap/checkpoint handling and persistence integration.
- `ios/Boxing/Models/AppStore.swift`: session start/checkpoint/history and assignment data.
- BUILD_STATUS.md documents persistent practice/workout history, local foundation planning and separate recording. This pass inspected source; it did not rerun those earlier device/tests.

Missing: a unified session type/launch contract covering guided audio versus live pads, camera/recognition inside training, supported-drill launch, broader curriculum/progression and results feeding meaningful next-training recommendations. The first foundations can be connected without completing every app feature.

## Sol's first task — one connected training path

Read BUILD_HANDOFF.md, BUILD_STATUS.md, FEATURE_CHECKLIST.md and this document. Inspect actual code and preserve the approved UI.

Before implementing recognition or commissioning coach art, make the single jab/cross training path explicit: session type, stable launch identity, optional source assignment/drill, configuration, lifecycle and durable result. Connect supported drill → briefing → existing guided player → truthful recap → Progress, preserving standalone start, Today assignment association, checkpoint recovery and no duplicate completion. Start with the working guided-audio path; add a distinct live-pads capability state rather than presenting audio as pad recognition.

Explain the small change set, implement/verify this foundation increment, update status/checklist, and stop before unrelated feature expansion. Keep the camera-first live-pad placement in this document as the destination. Next increment integrates the full-screen camera/target pipeline; model development and evaluation are explicitly part of completing Live Pad Training, not assumed to exist.

Do not claim Live Pad Training is complete until it detects actual observed responses on-device and has been benchmarked. A setup screen, animation or unscored prototype is an intermediate capability. Missing recognition must not block improving the genuine existing guided-training loop, nor generate simulated metrics.

## What BoxMaxxing actually establishes

The earlier broad feature report listed a dedicated Pad Coach route based on route inventory. Focused inspection now establishes that **#30384 PadCoachRoute renders Redirect href `/` in this build**, not an independent functional pad page. The workout route **#30519** renders **CoachedPlayer** with timeline, briefing, templateId, title, intensity, recording permission, mode, practice blocks and live-drill data. Settings renders **PadCoachSheet** for preferences.

Therefore the useful architectural reference is interactive coaching integrated into the workout/session flow, with configuration elsewhere. This does not establish exact paid-account card placement or every remotely configured entry point. Our Train/Today placement above is our design decision, not a claimed pixel-for-pixel copy of BoxMaxxing.

Retained source anchors (ordinary Hermes disassembly, not newly issued REA Evidence): `research/boxmaxxing/evidence/bundle.hasm` #30384 line1148709; #30519 line1158887; Settings PadCoachSheet use line1153878. Readable aid: `bundle.pseudo.js` route line1648334; workout CoachedPlayer use line1671047 onward. Original REA archive identities remain in `research/boxmaxxing/methodology.md`; the prior Android-provider limitation still applies. No target execution/private API/new extraction was needed for this focused follow-up.
