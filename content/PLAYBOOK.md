# BOX content playbook

The source of truth for short-form content. Every plan, script and result lives in `content/`, so any chat can pick it up.

## 1. What the reference videos do

### A. Jabmax "You're not too weak to hit hard" — 1M+, 61s, voiceover (the model to copy)

| Time | Beat | On screen |
|---|---|---|
| 0.0 | **Hook, a reassuring reversal of an insecurity:** "You're not too weak to hit hard." | Huge 2-line headline. A tense figure and a loose one, side by side, labelled red and green |
| 1.8 | **The real cause (villain):** "You're too tense." | Second line turns red |
| 3–8 | Show the mistake: "That's not a punch, that's a shove." | Figure pushes the bag, label "PUSHED" |
| 8–16 | **Proof from a real fight:** Bivol vs Canelo. Punch counters tick up (376 → 710) | Ring, two figures, live stat bars |
| 18.8 | **Mid-video re-hook (open loop):** "So how do you hit hard without trying?" | New scene |
| 21–24 | **Authority:** a named coach and a named method | — |
| 24.8 | **Product as the tool:** "Let's ask the Jabmax app." | App icon appears, HUD frame |
| 26–42 | **A 3-step mnemonic:** rope, stone, bow | Numbered headlines, glowing body parts, green = correct |
| 42–47 | The app judges the order: "Get it backwards and it tells you." | Green "CORRECT" and red "ARM WENT FIRST" pills |
| 47–54 | **Payoff on the pro** | Back to the fight scene |
| 54–60 | Mantra close plus CTA plus a comment question: "Who has the heaviest hands in boxing?" | App card, red waitlist pill |

Why it works:
- **The first 2 seconds are the whole game.** The hook removes an insecurity the viewer already has ("I'm too weak", "I'm too short", "I'm too slow") and blames something fixable instead. Every top performer in the screenshots uses this shape: *"Short doesn't lose to tall"* (389K), *"You're not too weak"* (196K), *"Your opponent isn't faster"*.
- **A new caption every ~2 seconds** and a new visual idea every 2–3 seconds. Nothing on screen holds still.
- **Text and voice say the same thing.** Muted viewers get the full story.
- **Real names and real numbers** (Bivol, Canelo, 700 punches) earn credibility and draw comments.
- **The product is the teacher inside the story,** not an ad at the end.
- **The ending gives viewers a reason to comment** (a question with a debatable answer).

Visual system: near-black background (#111), white/bone figure for "you" or the hero and dark grey for the opponent, red gloves. Red marks the mistake or emphasis, green marks the correct version. A heavy condensed all-caps headline sits top-left (line 1 white, line 2 red), with a tiny monospace eyebrow label above it ("HEAVY HANDS", "2022 · LAS VEGAS").

### B. boxmaxxing "Conor McGregor crazy knockout" — 476K likes, 33s, music only
- A famous moment recreated with mannequins. Fans recognise it instantly, and the "game-like" recreation feels new.
- Motion starts on frame 1. Slow motion on the impact, then multiple angles of the same punch.
- No text and no voice, so it works in any language. A trending phonk/hype track plays underneath.

### C. Combo clip — 7s, music only
- An 8-punch pad combo with a numbered label for each punch ("1 JAB", "3 LEFT HOOK") and a counter (01/08).
- It's short enough to loop 3–4×, and loops drive completion rate. Viewers save it to use as a drill.

## 2. Our three formats

| Pillar | Length | Audio | Purpose |
|---|---|---|---|
| **Breakdown** (Jabmax structure) | 20–30s | Voiceover plus quiet beat | Main growth and follow driver; carries the app |
| **Recreation** (famous moment) | 10–15s | Trending music, no voice | Reach and shares; fight-fan audience |
| **Combo loop** | 6–10s | Trending music | Saves, rewatches, challenge comments |

## 3. Hook rules (non-negotiable)

1. The hook must be **on screen and spoken within 0.5s.** No logo, no intro, no "hey guys".
2. **Text ≤ 6 words per line, 2 lines max.** Readable in 1 second.
3. **Motion on frame 1.** Something is already moving when the video starts.
4. Use one of the proven shapes:
   - **Insecurity reversal:** "You're not ___. You're ___." / "Short doesn't lose to tall."
   - **Contrarian claim:** "The jab isn't weak." / "The worst guard in boxing."
   - **Specific number:** "21 punches in 10 seconds." / "91 seconds."
   - **Challenge:** "Can you throw this in under 2 seconds?"
5. Add a re-hook question between 35% and 50% of the runtime ("So how do you get inside?").
6. End on a debatable comment question. Use a mantra when one fits.

## 4. CTA and claims rules

**Phase 1 (now): no CTA.** No app name, logo, screenshot or "link in bio" in videos, slideshows or captions. We end on a comment question instead. CTAs come back after a few days of consistent posting, as slide 4 of slideshows with 2 app screenshots, kept subtle, plus an App Store screenshot so people recognise the icon later.

When the app does appear: 
Only say BOX does what the shipping build does. Today that's: guided timed rounds with voice callouts, Live Pads (camera-based callouts and responses), personalised plans, drill library, video review, nutrition, coach chat. **Never say BOX grades technique, measures power or confirms "correct form."** The camera recognises supported punches and responses. It isn't a technique judge (see `COLLABORATOR_CONTEXT.md`). Keep fight stats verifiable; anything marked `VERIFY` in a script gets checked before posting.

## 5. Production

- Videos are coded as HTML canvas animations and rendered to 1080×1920 MP4 with `content/tools/render.mjs`. Each video is one file in `content/videos/`.
- Voiceover: Kokoro TTS (local, free). Lines live in `content/videos/<scene>.vo.json`, and each line starts on its scene beat. `content/tools/.venv/bin/python content/tools/voiceover.py <scene>` writes `out/<scene>_final.mp4` with the voice mixed in, and reports any line that runs past its beat. Default voice is `am_michael` at 1.12× speed. Samples of the other voices are in `out/voice-samples/`.
- Music: add a trending sound inside TikTok when posting, at low volume (10–20%) under the voice. Licensed sounds only work when added in-app.
- Results: `content/RESULTS.xlsx` (opens in Excel/Numbers, or upload to Google Sheets). Export it back into `content/` before asking for analysis.

## 6. Slideshows

### What the references do (Lino Leighton / Baller and Cal AI)
- **5 slides max:** a hook slide, then value slides. The CTA goes on slide 4 (phase 2 only).
- **Hook slide:** a "Here's exactly why you're…" / "5 ways to…" / "5 reasons you'll never…" / "How to… (step by step)" line ending in "...", then a small "(Swipe right)" or "(Step by step)" underneath.
- **Text:** TikTok's own font (TikTok Sans), Title Case, white with a black outline, centred around mid-screen, under 20 words per slide, one concrete tip per slide.
- **Photos:** real, candid, moody. Night, fog, dark gyms, empty pitches, athletes alone and usually facing away or faceless. Never stock-looking, never bright.
- **Sound:** a slowed or moody trending song that fits the photos ("FUZZ – Slowed", "your so quiet", "Century").
- **The value is real.** The slideshow has to be worth saving on its own.

### Workflow
1. **Images (you, ~10 min per batch):** search Pinterest with the terms below and save 25–30 photos into `content/slideshows/library/inbox/`. Grab more than you need, and don't worry about matching them to slides.
2. **Matching (me):** I look at every inbox photo, sort it into the library with a descriptive name, and assign the best one to each slide. One photo is used once per batch.
3. **Gaps (me, fal):** only when a slide has nothing fitting do I generate one with `content/tools/fal_images.py`, styled to look like the Pinterest shots. TikTok may require the "AI-generated" label on realistic AI photos, so this stays the exception.
4. **Render (me):** `content/tools/.venv/bin/python content/tools/slides.py <id>` writes the slides to `content/out/slideshows/<id>/1.jpg…` with the text baked in. You upload them in TikTok photo mode and add the sound.

Pinterest searches that fit our look: `boxing gym aesthetic dark`, `boxer from behind`, `heavy bag night`, `boxing hand wraps aesthetic`, `boxing ring empty dark`, `boxer silhouette`, `jump rope gym dark`, `boxing gloves moody`, `fight night aesthetic`, `early morning run fog`, `garage gym night`, `boxer sweat aesthetic`.

Most Pinterest photos belong to someone else. This format is standard on TikTok, but avoid photos with visible watermarks or recognisable faces of private people.
