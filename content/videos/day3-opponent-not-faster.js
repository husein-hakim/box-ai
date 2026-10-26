// Day 3 — "Your opponent isn't faster" (breakdown). Script: content/PLAN_DAYS_1-5.md
(function () {
  const { W, C, clamp, lerp, lerp2, inv, ease, punchCurve, punchAt, basePose, applyPunches, drawFigure, background,
    finish, headline, label, pill, impact, camera, questionCard, hexA, GUARD_REAR, REACH } = BOX;

  const GROUND = 1480, S = 6.2, HERO_X = 290, OPP_X = 640;
  // Beat times — set from the voiceover timing (voiceover.py output).
  const T = { sees: 2.0, pull: 4.1, tell: 7.7, how: 9.28, nopull: 10.58, path: 13.7, faster: 16.7, drill: 20.7, end: 24.45 };

  const bob = (t, ph = 0) => Math.sin((t + ph) * Math.PI * 2 * 1.7) * 0.9;

  // Wind-up cross over k∈[0,1]: pull back (0–0.45), hold (–0.55), fire (–0.75), return.
  function windupCross(pose, k) {
    if (k <= 0 || k >= 1) return;
    const back = k < 0.45 ? ease.inOut(k / 0.45) : k < 0.55 ? 1 : 1 - ease.out(inv(0.55, 0.68, k));
    pose.rear = lerp2(pose.rear, [-7, 4], back);
    pose.lean -= 7 * back; pose.hip[0] -= 2 * back;
    const ext = k < 0.55 ? 0 : punchCurve(inv(0.55, 1, k));
    applyPunches(pose, [{ type: 'cross', k: ext }]);
  }
  function slip(pose, k) {
    const s = Math.sin(clamp(k) * Math.PI);
    pose.hip[1] -= 11 * s; pose.lean += 26 * s; pose.headDy -= 2 * s; pose.front[0] += 3 * s;
  }
  // Where a cross from the guard starts and ends, for the green trail.
  function crossPath(ctx) {
    ctx.save(); ctx.globalAlpha = 0;
    const p0 = basePose(), p1 = applyPunches(basePose(), [{ type: 'cross', k: 1 }]);
    const a = drawFigure(ctx, { x: HERO_X, ground: GROUND, s: S, facing: 1, hero: true, pose: p0 }).rear;
    const b = drawFigure(ctx, { x: HERO_X, ground: GROUND, s: S, facing: 1, hero: true, pose: p1 }).rear;
    ctx.restore();
    return [a, b];
  }

  function hero(t) {
    const pose = basePose(); pose.hip[1] += bob(t);
    if (t < T.sees) windupCross(pose, inv(0.15, 1.75, t));
    else if (t < T.pull) windupCross(pose, inv(0, 1.6, (t - T.sees) * 0.42)); // slow-mo replay
    else if (t < T.tell) windupCross(pose, Math.min(0.5, inv(T.pull + 0.3, T.pull + 2.0, t) * 0.5)); // pull back and hold
    else if (t < T.how) windupCross(pose, 0.5); // frozen on the tell
    else if (t >= T.nopull && t < T.path) applyPunches(pose, [{ type: 'cross', k: punchAt(t, T.nopull + 0.5, 0.5) }, { type: 'cross', k: punchAt(t, T.nopull + 1.9, 0.5) }]);
    else if (t >= T.path && t < T.faster) {
      // hold extended, then return along the same line
      const out = ease.out(inv(T.path + 0.1, T.path + 0.4, t)), back = ease.inOut(inv(T.path + 1.3, T.path + 2.2, t));
      applyPunches(pose, [{ type: 'cross', k: out * (1 - back) }]);
    } else if (t >= T.faster && t < T.drill) {
      if (t < T.faster + 2.0) windupCross(pose, inv(T.faster + 0.2, T.faster + 1.6, t));
      else applyPunches(pose, [{ type: 'cross', k: punchAt(t, T.faster + 2.4, 0.42) }]);
    } else if (t >= T.drill) {
      applyPunches(pose, [
        { type: 'cross', k: punchAt(t, T.drill + 0.55, 0.42) },
        { type: 'jab', k: punchAt(t, T.drill + 1.45, 0.38) },
        { type: 'cross', k: punchAt(t, T.drill + 2.3, 0.42) },
      ]);
    }
    return pose;
  }

  function opp(t) {
    const pose = basePose(); pose.hip[1] += bob(t, 0.3);
    if (t < T.sees) slip(pose, inv(0.75, 1.55, t));
    else if (t < T.pull) slip(pose, inv(0.6, 1.4, (t - T.sees) * 0.42 + 0.0));
    else if (t >= T.faster && t < T.faster + 2.0) slip(pose, inv(T.faster + 0.65, T.faster + 1.45, t));
    else if (t >= T.faster + 2.0 && t < T.drill) {
      // late on the clean one: slips after it lands
      const hit = punchAt(t, T.faster + 2.5, 0.5); pose.headDx -= 3 * hit; pose.lean -= 7 * hit;
      slip(pose, inv(T.faster + 2.75, T.faster + 3.5, t) * 0.6);
    } else if (t >= T.nopull && t < T.path) {
      const hit = Math.max(punchAt(t, T.nopull + 0.6, 0.5), punchAt(t, T.nopull + 2.0, 0.5)); pose.headDx -= 3 * hit; pose.lean -= 7 * hit;
    }
    return pose;
  }

  function dashed(ctx, a, b, color, w = 5, dash = [16, 12]) {
    ctx.save(); ctx.setLineDash(dash); ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); ctx.restore();
  }
  function arrow(ctx, from, to, color, k = 1) {
    const b = lerp2(from, to, k), ang = Math.atan2(b[1] - from[1], b[0] - from[0]);
    ctx.save(); ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 8; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(from[0], from[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(b[0] + Math.cos(ang) * 22, b[1] + Math.sin(ang) * 22);
    ctx.lineTo(b[0] + Math.cos(ang + 2.4) * 22, b[1] + Math.sin(ang + 2.4) * 22);
    ctx.lineTo(b[0] + Math.cos(ang - 2.4) * 22, b[1] + Math.sin(ang - 2.4) * 22); ctx.closePath(); ctx.fill();
    ctx.restore();
  }
  function ring(ctx, p, r, color, a) {
    if (a <= 0) return;
    ctx.save(); ctx.strokeStyle = hexA(color, a); ctx.lineWidth = 5;
    ctx.beginPath(); ctx.arc(p[0], p[1], r, 0, Math.PI * 2); ctx.stroke(); ctx.restore();
  }
  function callout(ctx, txt, t, t0) {
    const k = inv(t0, t0 + 0.25, t), out = 1 - inv(t0 + 0.6, t0 + 0.8, t);
    if (k <= 0 || out <= 0) return;
    const s = ease.back(k);
    ctx.save(); ctx.globalAlpha = out; ctx.translate(540, 700); ctx.scale(s, s);
    ctx.fillStyle = C.red; ctx.beginPath(); ctx.arc(0, 0, 95, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = `bold 130px ${BOX.HEAD_FONT}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(txt, 0, 8); ctx.restore();
  }

  function draw(ctx, t) {
    background(ctx, t, { ground: GROUND });
    const replay = t >= T.sees && t < T.pull, frozen = t >= T.tell && t < T.how;
    ctx.save();
    const push = ease.inOut(inv(T.how, T.how + 1.4, t)) * (1 - ease.inOut(inv(T.nopull - 0.1, T.nopull + 0.3, t)));
    camera(ctx, 1 + 0.15 * push, 470, 1150);

    const fo = drawFigure(ctx, { x: OPP_X, ground: GROUND, s: S, facing: -1, hero: false, pose: opp(t) });
    const fh = drawFigure(ctx, { x: HERO_X, ground: GROUND, s: S, facing: 1, hero: true, pose: hero(t) });

    // Beat 0 and the comparison: MISS / LANDS labels.
    if (t > 1.15 && t < T.sees) label(ctx, 'MISS', fo.head[0] + 10, fo.head[1] - 120, { size: 34, alpha: 1 - inv(T.sees - 0.3, T.sees, t) });
    // Replay + pull-back: red ring on the rear glove/shoulder.
    if (replay || (t >= T.pull && t < T.tell)) {
      const pulse = 0.55 + 0.45 * Math.sin(t * 10);
      ring(ctx, fh.rear, 70 + 8 * pulse, C.red, 0.9);
      if (replay) label(ctx, 'REPLAY · 0.4X', 540, 1590, { size: 28, color: C.dim });
    }
    if (t >= T.pull && t < T.tell) {
      const k = ease.out(inv(T.pull + 0.4, T.pull + 1.4, t));
      arrow(ctx, [fh.rear[0] + 10, fh.rear[1] - 110], [fh.rear[0] - 150, fh.rear[1] - 110], C.red, k);
      label(ctx, 'BACKWARDS FIRST', fh.rear[0] - 60, fh.rear[1] - 160, { size: 28, alpha: k });
    }
    if (frozen) {
      ctx.fillStyle = 'rgba(232,53,46,0.06)'; ctx.fillRect(0, 0, W, 1920);
      ring(ctx, fh.rear, 78, C.red, 1);
      pill(ctx, 'THE TELL', fh.rear[0], fh.rear[1] - 130, { alpha: ease.out(inv(T.tell, T.tell + 0.2, t)), size: 32 });
      label(ctx, 'HE SEES THIS', fo.head[0] - 20, fo.head[1] - 120, { size: 28, color: C.text, alpha: ease.out(inv(T.tell + 0.5, T.tell + 0.8, t)) });
    }
    // Straight-line trail for the clean cross.
    if (t >= T.nopull && t < T.faster) {
      const [a, b] = crossPath(ctx);
      const k = ease.out(inv(T.nopull + 0.45, T.nopull + 0.8, t)) * (1 - inv(T.faster - 0.3, T.faster, t));
      ctx.save(); ctx.globalAlpha = k; dashed(ctx, a, b, C.green); ctx.restore();
      label(ctx, 'STRAIGHT FROM THE GUARD', 540, 1600, { size: 28, color: C.green, alpha: k });
      impact(ctx, fo.head[0] + 5, fo.head[1] + 5, inv(T.nopull + 0.62, T.nopull + 1.0, t), C.green, 80);
      impact(ctx, fo.head[0] + 5, fo.head[1] + 5, inv(T.nopull + 2.02, T.nopull + 2.4, t), C.green, 80);
      if (t >= T.path) {
        const r = ease.out(inv(T.path + 1.2, T.path + 1.6, t)) * (1 - inv(T.faster - 0.4, T.faster, t));
        ctx.save(); ctx.globalAlpha = r; arrow(ctx, [b[0] - 20, b[1] + 70], [a[0] + 20, a[1] + 70], C.green, ease.out(inv(T.path + 1.3, T.path + 2.1, t))); ctx.restore();
        // short exhale on the snap
        const ex = inv(T.path + 0.05, T.path + 0.6, t);
        if (ex > 0 && ex < 1) {
          ctx.save(); ctx.strokeStyle = hexA('#ffffff', 0.8 * (1 - ex)); ctx.lineWidth = 4;
          for (let i = 0; i < 3; i++) {
            const y = fh.head[1] + 6 + (i - 1) * 16, x0 = fh.head[0] + fh.headR + 6 + ex * 30;
            ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x0 + 40 + ex * 40, y + (i - 1) * 6); ctx.stroke();
          }
          ctx.restore();
          label(ctx, 'TSS', fh.head[0] + 120, fh.head[1] - 50, { size: 30, color: C.text, alpha: 1 - ex });
        }
      }
    }
    // Comparison: wind-up (red, he slips) then clean (green, lands).
    if (t >= T.faster && t < T.drill) {
      const first = t < T.faster + 2.0;
      pill(ctx, first ? 'WIND-UP' : 'CLEAN', 540, 1600, { bg: first ? C.red : C.green, color: first ? '#fff' : '#08140d', size: 30 });
      if (first && t > T.faster + 1.3) label(ctx, 'MISS', fo.head[0] + 10, fo.head[1] - 120, { size: 34 });
      if (!first) {
        impact(ctx, fo.head[0] + 5, fo.head[1] + 5, inv(T.faster + 2.5, T.faster + 2.9, t), C.green, 80);
        if (t > T.faster + 2.55) label(ctx, 'TOO LATE', fo.head[0] + 10, fo.head[1] - 120, { size: 34, color: C.green });
      }
    }
    ctx.restore();

    if (t >= T.drill && t < T.end) {
      callout(ctx, '2', t, T.drill + 0.25);
      callout(ctx, '1', t, T.drill + 1.15);
      callout(ctx, '2', t, T.drill + 2.0);
    }

    headline(ctx, t, -0.4, { eyebrow: 'HAND SPEED', l1: 'YOUR OPPONENT', l2: "ISN'T FASTER.", out: T.sees });
    headline(ctx, t, T.sees, { eyebrow: 'REPLAY', l1: 'HE SEES IT', l2: 'BEFORE YOU THROW.', out: T.pull, size: 116 });
    headline(ctx, t, T.pull, { eyebrow: 'WATCH THE RIGHT HAND', l1: 'THE', l2: 'PULL-BACK.', out: T.tell });
    headline(ctx, t, T.tell, { eyebrow: 'FREEZE', l1: "THAT'S", l2: 'THE TELL.', out: T.how });
    headline(ctx, t, T.how, { eyebrow: 'THE QUESTION', l1: 'SO HOW DO YOU', l2: 'HIDE IT?', out: T.nopull });
    headline(ctx, t, T.nopull, { eyebrow: 'THE FIX · 1/2', l1: 'NO', l2: 'PULL-BACK.', out: T.path });
    headline(ctx, t, T.path, { eyebrow: 'THE FIX · 2/2', l1: 'SAME PATH', l2: 'BACK.', out: T.faster });
    headline(ctx, t, T.faster, { eyebrow: 'SIDE BY SIDE', l1: 'HIDE THE START.', l2: 'LOOK FASTER.', out: T.drill });
    headline(ctx, t, T.drill, { eyebrow: 'DRILL', l1: 'FIRE OFF', l2: 'THE CALL.', out: T.end });

    finish(ctx, t);
    questionCard(ctx, t, T.end, { question: ['FASTEST HANDS', 'EVER?'] });
  }

  window.SCENE = { duration: 27.0, draw };
})();
