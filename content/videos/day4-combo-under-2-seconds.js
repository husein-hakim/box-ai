// Day 4 — "Can you throw this in under 2 seconds?" (combo loop, music only).
// Duration is a whole number of idle-bob cycles, so the last frame matches the first and the loop is seamless.
(function () {
  const { W, C, inv, ease, punchAt, basePose, applyPunches, drawFigure, background, finish, headline, label, pill,
    impact, hexA } = BOX;

  const GROUND = 1480, S = 6.4, HERO_X = 330, PAD_X = 650;
  const BOB_HZ = 1.7, D = 14 / BOB_HZ; // 8.235s
  const COMBO = [['jab', '1', 'JAB'], ['cross', '2', 'CROSS'], ['hook', '3', 'LEAD HOOK'], ['cross', '2', 'CROSS'],
    ['upper', '5', 'LEAD UPPERCUT'], ['cross', '2', 'CROSS']];
  const STEP = 0.3, FAST0 = 0.6, FAST_END = FAST0 + STEP * COMBO.length; // 1.8s of punching
  const SLOW0 = 3.25, SLOW = 0.45, SLOW_END = SLOW0 + (STEP * COMBO.length) / SLOW;

  const bob = (t, ph = 0) => Math.sin((t + ph) * Math.PI * 2 * BOB_HZ) * 0.9;

  // Combo-local time (seconds since the first punch) or null when not punching.
  function comboTime(t) {
    if (t >= FAST0 && t < FAST_END + 0.3) return t - FAST0;
    if (t >= SLOW0 && t < SLOW_END + 0.6) return (t - SLOW0) * SLOW;
    return null;
  }

  function draw(ctx, t) {
    background(ctx, t, { ground: GROUND });
    const ct = comboTime(t);
    const pose = basePose(); pose.hip[1] += bob(t);
    let idx = -1;
    if (ct !== null) {
      idx = Math.min(COMBO.length - 1, Math.floor(ct / STEP));
      applyPunches(pose, COMBO.map(([type], i) => ({ type, k: punchAt(ct, i * STEP, STEP * 1.25) })));
    }
    const pads = basePose(); pads.hip[1] += bob(t, 0.25); pads.lead = [16, 7]; pads.rear = [15, 1]; pads.lean = 2;
    const fp = drawFigure(ctx, { x: PAD_X, ground: GROUND, s: S, facing: -1, hero: false, pose: pads, oppGloves: '#22252a' });
    const fh = drawFigure(ctx, { x: HERO_X, ground: GROUND, s: S, facing: 1, hero: true, pose });

    // Pad impacts at full extension.
    if (ct !== null) COMBO.forEach(([type], i) => {
      const k = inv(i * STEP + 0.09, i * STEP + 0.26, ct);
      const hand = type === 'cross' ? fh.rear : fh.lead;
      if (k > 0 && k < 1) impact(ctx, hand[0] + 14, hand[1], k, '#ffffff', 60);
    });

    // Punch label + counter (left), stopwatch (right).
    const slow = t >= SLOW0 - 0.3 && t < SLOW_END + 0.6;
    if (idx >= 0) {
      const [, num, name] = COMBO[idx];
      const lt = ct - idx * STEP, k = ease.out(Math.min(1, lt / (slow ? 0.08 : 0.05)));
      ctx.save(); ctx.globalAlpha = k;
      ctx.font = `bold 190px ${BOX.HEAD_FONT}`; ctx.fillStyle = C.text; ctx.textAlign = 'left';
      ctx.fillText(num, 70, 690);
      const nw = ctx.measureText(num).width;
      ctx.font = `bold 64px ${BOX.HEAD_FONT}`; ctx.fillStyle = C.red; ctx.fillText(name, 70 + nw + 24, 690);
      ctx.restore();
      label(ctx, `${String(idx + 1).padStart(2, '0')} / 06`, 72, 500, { size: 28, color: C.mono, align: 'left' });
      // progress dashes
      for (let i = 0; i < COMBO.length; i++) {
        ctx.fillStyle = i <= idx ? C.red : 'rgba(255,255,255,0.18)'; ctx.fillRect(240 + i * 34, 494, 26, 6);
      }
    }
    let sw = 0;
    if (t >= FAST0 && t < FAST_END) sw = t - FAST0;
    else if (t >= FAST_END && t < D - 0.6) sw = FAST_END - FAST0;
    const done = t >= FAST_END && t < D - 0.6;
    ctx.save(); ctx.textAlign = 'right'; ctx.font = `bold 120px ${BOX.HEAD_FONT}`;
    ctx.fillStyle = done ? C.green : C.text; ctx.fillText(sw.toFixed(2) + 's', W - 150, 690); ctx.restore();
    label(ctx, 'STOPWATCH', W - 150, 520, { size: 24, color: C.mono, align: 'right' });
    if (done && t < SLOW0) pill(ctx, 'UNDER 2 SECONDS', 540, 1610, { bg: C.green, color: '#08140d', size: 30, alpha: ease.out(inv(FAST_END, FAST_END + 0.2, t)) });
    if (slow) label(ctx, 'SLOW-MO', 540, 1610, { size: 30, color: C.dim });
    if (t >= SLOW_END + 0.6) label(ctx, 'DROP YOUR TIME  ↓', 540, 1610, { size: 30, color: C.text, alpha: ease.out(inv(SLOW_END + 0.6, SLOW_END + 0.9, t)) * (1 - inv(D - 0.5, D - 0.2, t)) });

    headline(ctx, t, -1, { eyebrow: 'SPEED CHALLENGE', l1: 'CAN YOU THROW THIS', l2: 'IN UNDER 2 SECONDS?', size: 112 });
    finish(ctx, t);
  }

  window.SCENE = { duration: D, draw };
})();
