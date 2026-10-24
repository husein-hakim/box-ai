# Nutrition proposal policy — 20 October 2026

Latest user direction supersedes the earlier professional-policy launch gate: let the configured Qwen integration propose targets. Customers see only “coach” and “AI estimate”. No clinical policy review has been obtained or claimed.

- Generation uses age, height, weight, optional sex, activity, fueling goal, notes, training profile/history and actual accepted assignment durations.
- Qwen supplies calorie, protein, carbohydrate, fat, drinking-water and energy-need estimates, explanations and uncertainty. No target values or energy formulas are generated locally. Fixtures stay in tests.
- Only fueling/training/recovery is supported. No weight-loss, deficit, weight-cutting or fasting goal. The app rejects proposals below the AI-estimated energy need. That check does not independently establish the accuracy of the model’s energy estimate.
- Younger-user prompts explicitly account for growth, prohibit adult deficit formulas/restriction, and request parent/guardian/professional review. Age must match the submitted profile. The model can return needsSupport with no numeric proposal.
- Numerical sanity limits reject malformed/extreme values. Local 4/4/9 arithmetic checks macro-energy agreement within 5%. These checks are not clinical validation or personalized dietary advice.
- Users review/edit and explicitly accept. Input changes require regeneration; edited values are revalidated. Accepted targets and input remain in SwiftData and feed Fuel. Manual entries, food estimates, serving edits, water and totals remain independent.
- Live API behavior, dietary suitability and clinical review remain unverified. Do not describe generated estimates as medically approved.

Primary guidance consulted:
- USDA National Agricultural Library, DRI Calculator: https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator — individual requirements can differ from estimates.
- NIDDK, Take Charge of Your Health: https://www.niddk.nih.gov/health-information/weight-management/take-charge-health-guide-teenagers — growing teens may not need weight loss; restrictive eating can be harmful.

These sources inform request safeguards; their formulas or target tables were not copied into a local plan generator.
