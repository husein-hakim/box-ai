# BOX interface rules

Approved direction ("Ringside", 24 October 2026): photo-free near-black canvas with a soft colored header glow, charcoal cards, compressed italic display type, one signature red hero per screen, native iOS 26 Liquid Glass tab bar and navigation. Reference canvas: `design/premium-redesign/index.html`. Tokens and components: `ios/Boxing/Design/BoxStyle.swift`, `BoxComponents.swift`.

- Screen anatomy, in this order: header (`BoxPageHeader`) → one red hero for the focal action (`.boxHero()` + `BoxHeroButtonStyle`) → tool/stat grid (`BoxActionTile`, `BoxStatTile`) → compact history (`BoxRowGroup` + `BoxRow`). Only one red hero per screen.
- Type: `.boxDisplay()` for titles (SF Pro compressed black, slanted per line by `BoxObliqueRenderer`), `.boxSection()` for section headings, `.boxNumber()` for every number (tabular), `.boxEyebrow()` for small labels. Body copy stays SF Pro.
- Color meaning is fixed: red = boxing and primary action; amber (`BoxStyle.strength`) = strength, streaks, carbs; green (`conditioning`) = done/success; violet (`coach`) = coach and AI content, always labelled as an estimate; blue (`timer`) = timers, water, fat, defence.
- Primary actions use the red capsule `PrimaryButton` / `BoxPrimaryStyle`; on a red hero use `BoxHeroButtonStyle`.
- Secondary actions use BoxSecondaryStyle: neutral charcoal capsule, subtle border, 46-point minimum target. Never use accent-tinted maroon buttons or the native `.bordered` style.
- Scrolling screens use `.boxPage()` + `.boxScreen(tint:)`; native forms use `.boxFormStyle(tint:)`. Stagger top-level sections with `.boxEntrance(n)`.
- Design QA (Debug builds only): launch with `-boxScreen <name>` (see `Design/DesignPreviews.swift`) to open a screen on an in-memory store.
- Preserve native navigation/toolbar controls, the native TabView (Train · Review · Today · Fuel · Progress) and accessible Button semantics.
- Match the Today/Train typography, panels and spacing on every new feature.
- Respect Reduce Motion. Keep feedback brief and tied to a deliberate interaction.
- Product copy says “coach”, “personalized plan” or “AI estimate”; provider names and developer details belong only in developer documentation.
- Plans come from the configured AI service; no local or fixture plan generation in the customer flow. Local validation, execution and arithmetic remain local.
- No original demonstration media is available. Never display a fake play affordance or imply a demonstration exists.

Disabled primary buttons use neutral charcoal with muted text and a subtle neutral border. Do not dim red into maroon, and do not add accent-tinted secondary capsules.

## 23 October refinements

- Each tab has one job (tab order Train · Review · Today · Fuel · Progress, Today selected at launch): Today = next assigned action; Train = plan and practice; Review = recordings and coaching reports; Fuel = daily food/water/targets; Progress = actual completed work.
- Preserve Today's composition. Carry its spacing, warm white typography and charcoal panels into other pages. Use shared BoxPageHeader, BoxIconWell, BoxActionTile and compact history rows.
- Give a screen one focal action. Keep secondary tools compact; do not repeat promotional/feature-status banners on every page. Put detailed explanations in an appropriately named disclosure. Safety, consent, uncertainty and runtime failures must stay visible where they affect an action.
- Library discovery uses native search and filters. Plans expand into the exact prescribed sequence. Manual workout logs are secondary to guided execution.
- Record/import belongs in Review. Developer camera diagnostics belong in Profile & settings → Advanced. Do not remove the actual training camera entry.
- Liquid Glass belongs on floating utility controls and native navigation/toolbar surfaces, never every card. Use solid charcoal for reading and editable content, with an opaque Reduce Transparency fallback.
- Spring press scale is small (0.97; 0.9 for round icon buttons) and brief. Header entrances and changing totals are subtle. Respect Reduce Motion. Haptics mark deliberate presses, selections and successful saves; do not vibrate per recognition frame or animate camera targets decoratively.
- Show real records only. XP, levels, ranks and awards are derived from saved records (`Progression.compute`), never stored as a balance or granted for visual effect; every award has a stable ID so nothing counts twice. Never add fictional XP, bot leaderboards, nutrition grades, technique ratings or placeholder demonstrations for visual effect.
- A successful compile is not visual, accessibility, haptic or performance evidence. Record the exact device checks still needed.
