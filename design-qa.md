# Native UI design QA — first increment

final result: passed

Scope: visual QA of the no-photo Today design and focused session panel. This is not full-product completion, pixel-identical reproduction of Baller, or exhaustive latest-build runtime certification.

## Inputs / normalization
- Source: /Users/husein/Documents/box/design/today-reference.png, 853 × 1844 pixels; requested 390 × 844 logical-point app-only composition.
- Implementation: /Users/husein/Documents/box/design/qa/today-final.jpg, 368 × 800 optimized simulator pixels, iPhone 18 Pro, iOS 27. Native viewport is approximately 402 × 874 points; capture density is tool-optimized, not device pixels.
- Theme/state: dark Today, 19 October 2026 week. Source shows no configured days; simulator has Monday/Wednesday selected by verification. Source says Set days; configured state correctly says Edit days and adds schedule dots. These dots are not completion marks.
- Full view: /Users/husein/Documents/box/design/qa/comparison-final.png. Both images aspect-fit to the same 368 × 800 comparison cells without stretching. Native status/tab/safe-area chrome is retained and explicitly labeled; it consumes space absent from the app-only source. Compare hierarchy and component regions, not absolute Y positions across the OS chrome.
- Focused comparison: /Users/husein/Documents/box/design/qa/comparison-session.png. Source and native session panels cropped and aspect-fit together to inspect text, control, surface and copy. This is an analysis composite, not a shipping raster interface.

## Findings and comparison history
- Initial P2: build/library shortcuts fell under the first viewport's tab region. Evidence: design/qa/comparison-initial.png. Fixed by reducing home section gaps, header spacing, panel gaps/padding and shortcut minimum height. Post-fix evidence: comparison-final.png shows both shortcut labels and sublabels above the bar. Contextual coach entry remains reachable below by scrolling; the primary session and both core shortcuts are visible.
- Builder usability: the primary action was below scrolling form content. Fixed with a bottom safe-area inset for Start. Native inspection confirmed the button is exposed independently of the form and custom 4-round session opens with total 7:30.
- No remaining actionable P0/P1/P2 visual mismatches in the evaluated Today viewport. The native adaptation is intentional; it is not presented as a same-viewport pixel match.

## Required fidelity surfaces
- Typography: system sans, bold/rounded wordmark, heavy two-line headline, bold session title and readable secondary labels. Native header is smaller than the image's oversized lettering to retain controls beside OS chrome; Dynamic Type is supported. No title or shortcut truncation in final default-size capture.
- Spacing/layout: compact seven-day rail, one primary panel, two aligned shortcuts, native bottom navigation. Rounded card corners and native control spacing follow the selected style. Secondary coach/footer scroll below the initial viewport rather than compressing essential controls.
- Colors: charcoal base, tonal raised panels, thin gray separation, off-white primary text, muted secondary text and warm red emphasis. CTA fill is deeper than the mock's bright red to improve white-label contrast. No unnecessary overlapping glass effects; genuine native glass on navigation/controls where available.
- Image/assets: no hero image, photo avatar, illustration or image placeholder. All app icons are native SF Symbols; text/shapes are real SwiftUI, not a rasterized mockup. Reference PNG exists only outside the app target.
- Copy/state: main session, metadata, audio/unscored label, builder/library labels and dates match intent. Working-versus-unavailable states are explicit. No invented reaction time, correct-response count, punch power or technique score.

## Runtime validation and limits
- Build and launch succeeded; eight domain/storage tests passed.
- Observed guided start/cues, pause, stop confirmation, recap and saving; custom round count/total and builder-to-session handoff; library/detail navigation.
- Latest-build exhaustive tab interaction and manual relaunch persistence remain incompletely verified: simulator/Device Hub input and snapshot results were inconsistent after rebuilds. Storage survival and deduplication have regression tests. Do not infer full device coverage from this visual pass.
- Physical-device audio behavior, VoiceOver traversal, all accessibility text sizes, iOS 18 fallback execution, thermal/performance and camera behavior are not verified. No camera functionality is claimed.
- P3: final optical tuning of header weight and card radii can follow real-device review. No repeated decorative QA loop is required for this increment.

## Checklist
- [x] Both source and implementation opened and compared in one composite.
- [x] Main session panel inspected in a focused comparison.
- [x] Initial viewport issue fixed and recaptured.
- [x] Photos removed and real native controls retained.
- [x] Unbuilt recognition/services distinguished from working timer/audio behavior.
- [ ] Physical-device and exhaustive accessibility/runtime evaluation in future increments.
