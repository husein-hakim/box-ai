# BOX interface refresh — 23 October 2026

## Direction and evidence

Keep the existing photo-free Today screen as the design anchor. The nine competitor screenshots supplied by the user show useful hierarchy: a clear page heading, one focal action, compact supporting tools, grouped nutrition totals and consistent dark cards. BOX adopts those principles with its own typography, controls and real data. No competitor artwork, branding, fictional activity or ability scores were added.

This was a native-source implementation pass. The current app was not captured or visually audited at runtime: the user's previous no-simulator/test limit remains in effect. The reference screenshots are competitor evidence, not screenshots of this refresh. Older files under design/qa are historical and are not current validation.

Source inspection identified repeated setup explanations, multiple competing camera entrances, long expanded plan sequences, full recaps inside history lists, and food/target actions spread across banners. Those are the specific problems addressed here.

## Screen system

| Surface | Primary purpose | Presentation changes |
|---|---|---|
| Today | Start or resume assigned work | Existing composition preserved; obsolete development-preview footer removed |
| Train | Choose practice | Compact plan row; one Live Pads focal card; four consistent tools for drills, workouts, guided rounds and coach; diagnostics in Settings |
| Plans | Review and execute accepted assignments | Concise header; preferences in native menu; expandable exact sequence/rationale; strongest action on next/resumable session |
| Drills/exercises | Find a movement and practise | Native search/filter, compact stable-ID rows, clear prescription controls and numbered instructions; one shared-executor start |
| Workouts | Follow prescribed supporting work | Accepted workouts and ready routines separated; manual checklist placed in a disclosure below guided start |
| Review | Keep and inspect clips | One add menu when populated; clear record/import empty state; compact clip rows; notes, selected-frame review and evaluation details separated |
| Fuel | Log food and water | Real logged calories and editable targets, macro tracks, compact water/meals; one floating Add food / target-controls bar |
| Nutrition/meal sheets | Review before saving | Shared headers and grouping; estimate, consent and acceptance distinctions preserved |
| Progress | Inspect actual saved work | Real timed-work overview; Practices/Workouts switch; compact rows open full saved recaps |
| Coach | Read and write a conversation | Distinct message alignment, readable dark bubbles, persistent glass composer, native scrolling and explicit context disclosure |
| Camera setup/recap | Prepare and understand observations | Grouped practice/guidance controls; clear upper-body instructions and noncontact safety; detailed breakdown/diagnostics expandable |
| Profile/settings | Preferences and local-data controls | Real profile summary, feature status disclosed on demand, diagnostics in Advanced |

## Shared components and interaction

`ios/Boxing/Design/BoxStyle.swift` owns color, panels, rectangular primary/secondary controls and native glass icon buttons. `BoxComponents.swift` adds page headings, icon wells, action tiles, empty states, inline notices, bounded progress tracks, entrance motion and the glass utility-control fallback.

- Charcoal content remains readable and solid. Bright red marks deliberate primary actions, selected information and progress. Secondary buttons stay neutral; disabled controls do not fade into maroon.
- Use native tabs, navigation, menus, pickers and accessible Buttons. Preserve normal back navigation on pushed pages.
- Press feedback scales to 0.975 with a brief spring and light haptic. Successful persistence has a success haptic; filters/tabs/day selection use selection feedback.
- Reduce Motion removes decorative entrance/scale movement. Reduce Transparency supplies opaque alternatives to new glass utility controls and icon buttons. Large accessibility text stacks the Train tool grid, macro cards and Progress metrics vertically.
- Haptics/animations do not drive training state, cue onset or measured performance. Live target rendering, calibration, recognition and response timing were left intact.
- Details can collapse; operational errors, consent, safety and uncertainty remain explained. No unsupported feature is represented as a working result.

## Verification boundary

The first generic-iOS Debug compile found one view-complexity failure in clip detail. Extracting metadata, review actions, saved-report row and evaluation details resolved it; the necessary recheck passed. No Swift warnings/errors remain. The existing App Intents metadata warning is unchanged.

No simulator, unit/UI test, phone installation, screenshot capture or external AI request ran. No SwiftData schema, model, record migration or credential was changed. Existing session/result/checkpoint behavior is reused.

Before calling the refresh visually verified, review it on the physical iPhone: all five tabs and back navigation, plan/drill/workout launch and resume, food/target menus, clip editing/review, chat and keyboard, large text/VoiceOver, Reduce Motion/Transparency, native tab-bar clearance and the feel of the haptics. BUILD_STATUS.md lists the manual checks and continuing external dependencies.
