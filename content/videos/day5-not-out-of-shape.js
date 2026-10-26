// Day 5 — "You're not out of shape" (breathing breakdown). Script: content/PLAN_DAYS_1-5.md
(function () {
  const { W, C, clamp, lerp, inv, ease, punchAt, basePose, applyPunches, drawFigure, background, finish, headline,
    label, pill, impact, questionCard, hexA } = BOX;

  const GROUND = 1480, S = 6.6, HERO_X = 330, BAG_X = 660, PIVOT_Y = 640;
  const T = { hold: 1.25, lock: 2.75, cement: 4.9, teeth: 7.55, tss: 11.35, tank: 14.3, rounds: 16.7, end: 19.7 };

  const bob = t => Math.sin(t * Math.PI * 2 * 1.7) * 0.9;

  // Every punch thrown: [time, type, duration]. Bag swing and impacts are derived from this list.
  const P = [];
  const add = (t, type, dur = 0.42) => P.push([t, type, dur]);
  add(0.15, 'jab'); add(0.5, 'cross'); add(0.95, 'hook');                       // hook beat: busy combo
  add(1.5, 'jab'); add(1.85, 'cross'); add(2.3, 'jab');                         // holding breath
  add(2.95, 'jab'); add(3.45, 'cross'); add(4.0, 'hook');                       // chest locks
  add(5.4, 'jab', 0.75); add(6.4, 'cross', 0.8);                                 // cement arms: slow
  add(8.0, 'jab'); add(8.9, 'cross'); add(9.9, 'jab'); add(10.5, 'cross');      // through the teeth
  add(11.55, 'jab'); add(12.17, 'cross'); add(13.01, 'hook');                    // jab-tss, cross-tss, hook-tss
  add(14.6, 'jab'); add(15.0, 'cross'); add(15.6, 'hook'); add(16.1, 'cross');  // tank full
  add(17.0, 'jab'); add(17.35, 'cross'); add(18.0, 'jab'); add(18.35, 'cross'); add(18.75, 'hook'); add(19.2, 'cross');
  const HIT = 0.13; // time from punch start to contact

  const exhaling = t => t >= T.teeth && t < T.end;

  function bagSwing(t) {
    let a = 0;
    for (const [t0, type] of P) {
      const dt = t - (t0 + HIT);
      if (dt > 0 && dt < 2.5) a += (type === 'hook' ? 1.6 : 1.1) * Math.sin(dt * 6) * Math.exp(-dt * 2.2);
    }
    return a * 2.2; // degrees
  }

  function heavyBag(ctx, t) {
    const ang = (bagSwing(t) * Math.PI) / 180;
    ctx.save(); ctx.translate(BAG_X, PIVOT_Y); ctx.rotate(-ang);
    ctx.fillStyle = '#4a4f57'; ctx.fillRect(-60, -160, 120, 12);
    ctx.strokeStyle = '#5a5f68'; ctx.lineWidth = 6;
    ctx.beginPath(); ctx.moveTo(0, -150); ctx.lineTo(0, 0); ctx.moveTo(0, 0); ctx.lineTo(-55, 90); ctx.moveTo(0, 0); ctx.lineTo(55, 90); ctx.stroke();
    ctx.fillStyle = '#34373e'; BOX.roundRect(ctx, -80, 90, 160, 560, 60); ctx.fill();
    ctx.fillStyle = C.red; ctx.fillRect(-80, 300, 160, 46);
    ctx.restore();
  }

  function hero(t) {
    const pose = basePose(); pose.hip[1] += bob(t);
    const cement = t >= T.cement && t < T.teeth;
    if (cement) {
      const k = ease.out(inv(T.cement, T.cement + 0.6, t));
      pose.lead = [lerp(12, 13, k), lerp(5, -3, k)]; pose.rear = [lerp(7, 8, k), lerp(10, 0, k)];
      pose.lean -= 4 * k; pose.headDy -= 1.5 * k;
    }
    applyPunches(pose, P.map(([t0, type, dur]) => ({ type, k: punchAt(t, t0, dur) })));
    return pose;
  }

  function lungs(ctx, f, color, a, scale = 1) {
    if (a <= 0) return;
    const c = [lerp(f.hip[0], f.chest[0], 0.72) + 4, lerp(f.hip[1], f.chest[1], 0.72)];
    ctx.save();
    [-1, 1].forEach(sd => {
      const g = ctx.createRadialGradient(c[0] + sd * 16, c[1], 0, c[0] + sd * 16, c[1], 60 * scale);
      g.addColorStop(0, hexA(color, 0.85 * a)); g.addColorStop(1, hexA(color, 0));
      ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(c[0] + sd * 16, c[1], 34 * scale, 56 * scale, 0, 0, Math.PI * 2); ctx.fill();
    });
    ctx.restore();
  }

  function puff(ctx, f, k, withLabel) {
    if (k <= 0 || k >= 1) return;
    ctx.save(); ctx.strokeStyle = hexA('#ffffff', 0.85 * (1 - k)); ctx.lineWidth = 5; ctx.lineCap = 'round';
    for (let i = 0; i < 3; i++) {
      const y = f.head[1] + 14 + (i - 1) * 16, x0 = f.head[0] + f.headR + 4 + k * 30;
      ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x0 + 40 + k * 50, y + (i - 1) * 8); ctx.stroke();
    }
    ctx.restore();
    if (withLabel) label(ctx, 'TSS', f.head[0] + 70, f.head[1] - 90, { size: 40, color: C.text, alpha: 1 - k, font: BOX.HEAD_FONT });
  }

  // Air meter on the left: drains while holding, refills while exhaling rhythmically.
  function airLevel(t) {
    if (t < T.hold) return 1;
    if (t < T.teeth) return 1 - 0.85 * ease.out(inv(T.hold, T.teeth - 0.4, t));
    if (t < T.tank) return 0.15 + 0.35 * inv(T.teeth, T.tank, t);
    return 0.5 + 0.5 * ease.out(inv(T.tank, T.tank + 1.5, t));
  }
  function airMeter(ctx, t) {
    if (t < T.hold - 0.2) return;
    const a = ease.out(inv(T.hold - 0.2, T.hold + 0.2, t));
    const lv = airLevel(t), x = 70, y0 = 760, h = 520, w = 26;
    const col = lv < 0.4 ? C.red : lv > 0.7 ? C.green : '#e7c14a';
    ctx.save(); ctx.globalAlpha = a;
    ctx.fillStyle = 'rgba(255,255,255,0.1)'; BOX.roundRect(ctx, x, y0, w, h, 13); ctx.fill();
    ctx.fillStyle = col; BOX.roundRect(ctx, x, y0 + h * (1 - lv), w, h * lv, 13); ctx.fill();
    ctx.restore();
    label(ctx, 'AIR', x + w / 2, y0 - 34, { size: 26, color: C.mono, alpha: a });
    label(ctx, `${Math.round(lv * 100)}%`, x + w / 2, y0 + h + 36, { size: 26, color: col, alpha: a });
  }

  function draw(ctx, t) {
    background(ctx, t, { ground: GROUND });
    heavyBag(ctx, t);
    const f = drawFigure(ctx, { x: HERO_X, ground: GROUND, s: S, facing: 1, hero: true, pose: hero(t) });

    // Impacts on the bag.
    for (const [t0, type] of P) {
      const k = inv(t0 + HIT - 0.02, t0 + HIT + 0.3, t);
      const hand = type === 'cross' ? f.rear : f.lead;
      if (k > 0 && k < 1) impact(ctx, hand[0] + 16, hand[1], k, exhaling(t) ? C.green : '#ffffff', 55);
    }

    // Lungs: red while holding/locked, green once breathing.
    if (t >= T.hold && t < T.teeth) {
      let flash = 0;
      if (t >= T.lock) for (const [t0] of P) flash = Math.max(flash, 1 - clamp(Math.abs(t - (t0 + HIT)) / 0.25));
      lungs(ctx, f, C.red, 0.45 + 0.55 * flash, 1 + 0.15 * flash);
      if (t >= T.lock && t < T.cement) {
        for (const [t0] of P) if (t > t0 + HIT && t < t0 + HIT + 0.45 && t0 >= T.lock)
          label(ctx, 'LOCKED', f.chest[0] - 40, f.chest[1] - 40, { size: 26, alpha: 1 - inv(t0 + HIT + 0.25, t0 + HIT + 0.45, t) });
      }
    }
    if (t >= T.teeth && t < T.end) lungs(ctx, f, C.green, t >= T.tank ? 0.9 : 0.5);

    if (t >= T.hold && t < T.lock) pill(ctx, 'HOLDING', f.head[0] + 40, f.head[1] - 130, { size: 26, alpha: ease.out(inv(T.hold, T.hold + 0.2, t)) });

    // Cement arms: round clock and heavy arrows.
    if (t >= T.cement && t < T.teeth) {
      const sec = Math.floor(lerp(0, 9, inv(T.cement, T.teeth, t)));
      label(ctx, `ROUND 2 · 2:${String(sec).padStart(2, '0')}`, 540, 1600, { size: 34, color: C.text });
      const k = ease.out(inv(T.cement + 0.4, T.cement + 0.9, t));
      [f.lead, f.rear].forEach(p => {
        ctx.save(); ctx.globalAlpha = k; ctx.strokeStyle = C.red; ctx.lineWidth = 6; ctx.lineCap = 'round';
        const x = p[0] + 4, y = p[1] + 60 + 10 * Math.sin(t * 5);
        ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y + 60); ctx.moveTo(x - 14, y + 46); ctx.lineTo(x, y + 60); ctx.lineTo(x + 14, y + 46); ctx.stroke();
        ctx.restore();
      });
      label(ctx, 'HEAVY', f.lead[0] + 10, f.lead[1] + 160, { size: 26, alpha: k });
    }

    // Exhale on every punch from "through the teeth" on.
    if (exhaling(t)) for (const [t0] of P) if (t0 >= T.teeth) puff(ctx, f, inv(t0 + 0.02, t0 + 0.5, t), t0 >= T.tss && t0 < T.tank);

    // Three rounds.
    if (t >= T.rounds && t < T.end) {
      for (let i = 0; i < 3; i++) {
        const on = t > T.rounds + 0.5 + i * 0.7, x = 540 + (i - 1) * 90;
        ctx.fillStyle = on ? C.green : 'rgba(255,255,255,0.15)'; ctx.beginPath(); ctx.arc(x, 1600, 22, 0, Math.PI * 2); ctx.fill();
      }
      label(ctx, 'ROUNDS', 540, 1660, { size: 24, color: C.mono });
    }
    airMeter(ctx, t);

    headline(ctx, t, -0.4, { eyebrow: 'CARDIO', l1: "YOU'RE NOT", l2: 'OUT OF SHAPE.', out: T.hold });
    headline(ctx, t, T.hold, { eyebrow: 'THE REAL PROBLEM', l1: "YOU'RE HOLDING", l2: 'YOUR BREATH.', out: T.lock });
    headline(ctx, t, T.lock, { eyebrow: 'EVERY PUNCH', l1: 'YOUR CHEST', l2: 'LOCKS UP.', out: T.cement });
    headline(ctx, t, T.cement, { eyebrow: 'ROUND 2', l1: 'ROUND 2:', l2: 'CEMENT ARMS.', out: T.teeth });
    headline(ctx, t, T.teeth, { eyebrow: 'THE FIX', l1: 'THROUGH', l2: 'THE TEETH.', out: T.tss });
    headline(ctx, t, T.tss, { eyebrow: 'ONE BREATH PER PUNCH', l1: 'TSS. TSS.', l2: 'TSS.', out: T.tank });
    headline(ctx, t, T.tank, { eyebrow: 'WHY IT WORKS', l1: 'CORE TIGHT.', l2: 'TANK FULL.', out: T.rounds });
    headline(ctx, t, T.rounds, { eyebrow: 'YOUR NEXT SESSION', l1: '3 ROUNDS.', l2: 'TRY IT.', out: T.end });

    finish(ctx, t);
    questionCard(ctx, t, T.end, { question: ['DO YOU HOLD', 'YOUR BREATH?'] });
  }

  window.SCENE = { duration: 23.0, draw };
})();
