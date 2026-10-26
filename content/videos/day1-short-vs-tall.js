// Day 1 — "Short doesn't lose to tall" (breakdown). Script: content/PLAN_DAYS_1-5.md
(function () {
  const { W, C, clamp, lerp, inv, ease, punchAt, basePose, applyPunches, drawFigure, background, finish,
    headline, label, pill, impact, camera, questionCard, hexA } = BOX;

  const GROUND = 1480;
  const HERO_S = 6.3, OPP_S = 7.3;
  const OUT_X = 270, OPP_X = 770, IN_X = 505;

  // Beat times (seconds) — match the voiceover table.
  const T = { reach: 2.45, jab: 4.4, tyson: 7.6, how: 12.22, angle: 14.0, slip: 17.4, inside: 20.6, mantra: 24.6, end: 27.0 };

  const bob = (t, ph = 0) => Math.sin((t + ph) * Math.PI * 2 * 1.7) * 0.9;

  function heroState(t) {
    const st = { x: OUT_X, ground: GROUND, s: HERO_S, pose: basePose(), punches: [] };
    st.pose.hip[1] += bob(t);
    // Beat 3: hero's jab falls short; head snaps from his jab.
    if (t >= T.jab && t < T.tyson) {
      const hit = punchAt(t, T.jab + 0.45, 0.5);
      st.pose.headDx -= 3 * hit; st.pose.lean -= 6 * hit;
      st.punches.push({ type: 'jab', k: punchAt(t, T.jab + 1.75, 0.6) });
    }
    if (t >= T.tyson && t < T.how) {
      st.punches.push({ type: 'hook', k: punchAt(t, T.tyson + 1.6, 0.45) }, { type: 'cross', k: punchAt(t, T.tyson + 2.05, 0.42) });
    }
    // Beat 6: step in on an angle — moves up/back in depth and forward.
    if (t >= T.angle && t < T.slip) {
      const k = ease.inOut(inv(T.angle + 0.5, T.angle + 1.5, t));
      st.x = lerp(OUT_X, IN_X - 30, k);
      st.ground = GROUND - 60 * Math.sin(k * Math.PI) - 25 * k;
      st.s = HERO_S * (1 - 0.06 * Math.sin(k * Math.PI));
      st.pose.front[0] += 6 * Math.sin(k * Math.PI);
    }
    // Beat 7: slip (head off the line) then step in.
    if (t >= T.slip && t < T.inside) {
      const slip = Math.sin(clamp(inv(T.slip + 0.55, T.slip + 1.25, t)) * Math.PI);
      st.pose.hip[1] -= 6 * slip; st.pose.lean += 16 * slip; st.pose.hip[0] += 3 * slip;
      st.pose.front[0] += 4 * slip;
      const k = ease.inOut(inv(T.slip + 1.25, T.slip + 2.1, t));
      st.x = lerp(OUT_X, IN_X, k);
    }
    if (t >= T.inside) {
      st.x = IN_X;
      st.punches.push(
        { type: 'hook', k: punchAt(t, T.inside + 0.6, 0.45) },
        { type: 'rupper', k: punchAt(t, T.inside + 1.25, 0.5) },
        { type: 'hook', k: punchAt(t, T.inside + 1.95, 0.45) },
      );
    }
    applyPunches(st.pose, st.punches);
    return st;
  }

  function oppState(t, hero) {
    const st = { x: OPP_X, ground: GROUND, s: OPP_S, pose: basePose(), punches: [] };
    st.pose.hip[1] += bob(t, 0.3);
    if (t >= T.jab && t < T.tyson) {
      st.punches.push({ type: 'jab', k: punchAt(t, T.jab + 0.25, 0.6) });
      st.x -= 70 * Math.sin(clamp(inv(T.jab, T.jab + 1.3, t)) * Math.PI);
    }
    if (t >= T.angle && t < T.slip) st.punches.push({ type: 'jab', k: punchAt(t, T.angle + 0.85, 0.55) });
    if (t >= T.slip && t < T.inside) st.punches.push({ type: 'jab', k: punchAt(t, T.slip + 0.6, 0.6) });
    if (t >= T.inside && t < T.mantra) {
      // Getting hit inside: head snaps on each landed shot.
      const h = Math.max(punchAt(t, T.inside + 0.75, 0.5), punchAt(t, T.inside + 1.45, 0.5), punchAt(t, T.inside + 2.1, 0.5));
      st.pose.headDx -= 3 * h; st.pose.lean -= 7 * h;
      st.pose.lead = [6, 10]; st.pose.rear = [4, 12];
    }
    applyPunches(st.pose, st.punches);
    return st;
  }

  // Dashed line helper.
  function dashed(ctx, x1, y1, x2, y2, color, w = 4, dash = [14, 12]) {
    ctx.save(); ctx.setLineDash(dash); ctx.strokeStyle = color; ctx.lineWidth = w;
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); ctx.restore();
  }

  function heightTag(ctx, x, top, ground, text, k, color) {
    if (k <= 0) return;
    const yTop = lerp(ground, top, ease.out(k));
    ctx.save(); ctx.strokeStyle = hexA(color, 0.8); ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x, ground); ctx.lineTo(x, yTop); ctx.moveTo(x - 14, yTop); ctx.lineTo(x + 14, yTop); ctx.stroke();
    ctx.restore();
    label(ctx, text, x, yTop - 40, { color, size: 40, alpha: ease.out(inv(0.5, 1, k)) });
  }

  function draw(ctx, t) {
    background(ctx, t, { ground: GROUND });
    ctx.save();
    // Camera: push in on "how do you get inside?" then ease back.
    const push = ease.inOut(inv(T.how, T.how + 1.6, t)) * (1 - ease.inOut(inv(T.angle - 0.1, T.angle + 0.4, t)));
    camera(ctx, 1 + 0.18 * push, 540, 1250);

    const hero = heroState(t);
    const opp = oppState(t, hero);
    const dimFighters = t >= T.tyson && t < T.how ? 0.2 + 0.65 * (1 - ease.out(inv(T.tyson, T.tyson + 0.4, t))) + 0.65 * ease.out(inv(T.how - 0.4, T.how, t)) : 1;

    // Beat 2: reach rulers at shoulder height — his reaches your head, yours stops short.
    if (t >= T.reach && t < T.jab + 0.2) {
      const k = ease.out(inv(T.reach + 0.1, T.reach + 0.9, t)), a = 1 - inv(T.jab, T.jab + 0.2, t);
      const oy = 720, hy = 800;
      const oTip = OPP_X - 470 * k, hTip = OUT_X + 235 * k;
      ctx.save(); ctx.globalAlpha = a; ctx.lineWidth = 6; ctx.lineCap = 'round';
      ctx.strokeStyle = C.red; ctx.beginPath(); ctx.moveTo(OPP_X, oy); ctx.lineTo(oTip, oy); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(oTip, oy - 18); ctx.lineTo(oTip, oy + 18); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.75)'; ctx.beginPath(); ctx.moveTo(OUT_X, hy); ctx.lineTo(hTip, hy); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(hTip, hy - 18); ctx.lineTo(hTip, hy + 18); ctx.stroke();
      ctx.restore();
      label(ctx, 'HIS REACH', (OPP_X + oTip) / 2, oy - 40, { alpha: a * k, size: 30 });
      label(ctx, 'YOUR REACH', (OUT_X + hTip) / 2, hy + 42, { alpha: a * k, size: 30, color: C.text });
    }

    // Beat 6: diagonal step path.
    if (t >= T.angle && t < T.slip) {
      const k = ease.out(inv(T.angle + 0.1, T.angle + 0.6, t)) * (1 - inv(T.slip - 0.3, T.slip, t));
      ctx.save(); ctx.globalAlpha = k;
      dashed(ctx, OUT_X, GROUND + 4, OUT_X + 110, GROUND - 70, C.green, 5);
      dashed(ctx, OUT_X + 110, GROUND - 70, IN_X - 30, GROUND - 25, C.green, 5);
      ctx.restore();
    }

    const fo = drawFigure(ctx, { ...opp, facing: -1, hero: false, alpha: dimFighters });
    const fh = drawFigure(ctx, { ...hero, facing: 1, hero: true, alpha: dimFighters,
      glow: t >= T.slip && t < T.inside ? { part: 'head', color: C.green, k: Math.sin(clamp(inv(T.slip + 0.5, T.slip + 1.4, t)) * Math.PI), r: 18 } : null });

    // Beat 1: height tags.
    if (t < T.reach + 0.3) {
      const k = inv(0.15, 0.75, t), a = 1 - inv(T.reach, T.reach + 0.3, t);
      ctx.save(); ctx.globalAlpha = a;
      heightTag(ctx, OUT_X - 130, fh.head[1] - fh.headR, GROUND, `5'7"`, k, C.text);
      heightTag(ctx, OPP_X + 140, fo.head[1] - fo.headR, GROUND, `6'4"`, inv(0.3, 0.9, t), C.red);
      ctx.restore();
    }

    // Beat 3: his jab lands, yours falls short.
    if (t >= T.jab && t < T.tyson) {
      impact(ctx, fh.head[0] - 10, fh.head[1], inv(T.jab + 0.4, T.jab + 0.85, t), C.red, 80);
      if (t > T.jab + 0.35 && t < T.jab + 1.4) label(ctx, 'LANDS', fh.head[0] - 40, fh.head[1] - 120, { size: 30, alpha: 1 - inv(T.jab + 1.1, T.jab + 1.4, t) });
      const gk = inv(T.jab + 1.9, T.jab + 2.1, t) * (1 - inv(T.tyson - 0.25, T.tyson, t));
      if (gk > 0) {
        const gx1 = fh.lead[0] + 40, gx2 = fo.head[0] - fo.headR;
        ctx.save(); ctx.globalAlpha = gk;
        dashed(ctx, gx1, fh.lead[1], gx2, fh.lead[1], C.red, 5, [10, 8]);
        ctx.restore();
        label(ctx, 'SHORT', (gx1 + gx2) / 2, fh.lead[1] - 44, { size: 30, alpha: gk });
      }
    }

    // Beat 5: long-range bracket.
    if (t >= T.how && t < T.angle) {
      const k = ease.out(inv(T.how + 0.3, T.how + 0.8, t));
      const y = GROUND + 50, x1 = fh.toWorld([18, 0])[0] + 20, x2 = fo.toWorld([18, 0])[0] - 20;
      ctx.save(); ctx.globalAlpha = k; ctx.strokeStyle = C.red; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.moveTo(x1, y - 16); ctx.lineTo(x1, y); ctx.lineTo(x2, y); ctx.lineTo(x2, y - 16); ctx.stroke(); ctx.restore();
      label(ctx, 'DANGER ZONE', (x1 + x2) / 2, y + 40, { size: 24, alpha: k });
    }

    // Beat 6: his jab misses the angled step.
    if (t >= T.angle + 0.9 && t < T.angle + 2.2) label(ctx, 'MISS', fo.lead[0] - 30, fo.lead[1] - 80, { size: 32, alpha: 1 - inv(T.angle + 1.9, T.angle + 2.2, t) });
    if (t >= T.slip + 0.7 && t < T.slip + 2.0) label(ctx, 'MISS', fo.lead[0] - 30, fo.lead[1] - 110, { size: 32, alpha: 1 - inv(T.slip + 1.7, T.slip + 2.0, t) });

    // Beat 8: inside shots land.
    if (t >= T.inside && t < T.mantra) {
      [[0.7, 'lead'], [1.38, 'rear'], [2.05, 'lead']].forEach(([dt, h]) =>
        impact(ctx, fo.head[0] - 6, fo.head[1] + 10, inv(T.inside + dt, T.inside + dt + 0.4, t), C.green, 80));
      const k = ease.out(inv(T.inside + 0.2, T.inside + 0.6, t)) * (1 - inv(T.mantra - 0.3, T.mantra, t));
      pill(ctx, 'HIS REACH: USELESS', 540, GROUND + 110, { bg: C.green, color: '#08140d', alpha: k, size: 26 });
    }
    ctx.restore();

    // Beat 4: Tyson counter (screen space).
    if (t >= T.tyson && t < T.how) {
      const k = inv(T.tyson + 0.6, T.tyson + 2.6, t);
      const n = Math.round(44 * ease.out(k));
      const a = ease.out(inv(T.tyson + 0.4, T.tyson + 0.7, t)) * (1 - inv(T.how - 0.3, T.how, t));
      ctx.save(); ctx.globalAlpha = a; ctx.textAlign = 'center';
      ctx.font = `bold 360px ${BOX.HEAD_FONT}`; ctx.fillStyle = C.red; ctx.fillText(String(n).padStart(2, '0'), W / 2, 1180);
      ctx.restore();
      label(ctx, 'KNOCKOUTS · 50 WINS', W / 2, 1250, { size: 28, color: C.dim, alpha: a });
    }

    // Headlines.
    headline(ctx, t, -0.4, { eyebrow: 'SHORT FIGHTERS', l1: "SHORT DOESN'T", l2: 'LOSE TO TALL.', out: T.reach });
    headline(ctx, t, T.reach, { eyebrow: 'THE REAL PROBLEM', l1: 'THEY LOSE', l2: 'AT LONG RANGE.', out: T.jab });
    headline(ctx, t, T.jab, { eyebrow: 'LONG RANGE', l1: 'HIS JAB LANDS.', l2: "YOURS DOESN'T.", out: T.tyson });
    headline(ctx, t, T.tyson, { eyebrow: 'IRON MIKE · 1985–2005', l1: `5'10".`, l2: '44 KNOCKOUTS.', out: T.how });
    headline(ctx, t, T.how, { eyebrow: 'THE QUESTION', l1: 'SO HOW DO YOU', l2: 'GET INSIDE?', out: T.angle });
    headline(ctx, t, T.angle, { eyebrow: 'GETTING INSIDE · 1/3', l1: '1. STEP IN', l2: 'ON AN ANGLE.', out: T.slip });
    headline(ctx, t, T.slip, { eyebrow: 'GETTING INSIDE · 2/3', l1: '2. SLIP,', l2: 'THEN STEP.', out: T.inside });
    headline(ctx, t, T.inside, { eyebrow: 'GETTING INSIDE · 3/3', l1: '3. STAY', l2: 'INSIDE.', out: T.mantra });
    headline(ctx, t, T.mantra, { eyebrow: 'REMEMBER', l1: "RANGE ISN'T HEIGHT.", l2: "IT'S A CHOICE.", out: T.end, size: 112 });

    finish(ctx, t);
    questionCard(ctx, t, T.end, { question: ['HOW TALL', 'ARE YOU?'] });
  }

  window.SCENE = { duration: 29.5, draw };
})();
