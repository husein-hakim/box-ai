// BOX short-form animation engine. Deterministic: draw(t) renders the frame at time t (seconds).
// Canvas is 1080x1920. Figures are 2D side-view boxers posed with two-bone IK.
(function () {
  const W = 1080, H = 1920;
  const C = {
    bg: '#0d0e10', bg2: '#17191d',
    hero: '#ece6db', heroBack: '#b9b2a6', heroLimb: '#d8d1c4',
    opp: '#50555e', oppBack: '#3a3e45', oppLimb: '#474c54',
    red: '#e8352e', green: '#3ddc84', text: '#f4f1ea', dim: '#8b8f97', mono: '#9aa0a8',
  };
  const HEAD_FONT = '"DIN Condensed", "Impact", sans-serif';
  const MONO_FONT = '"SF Mono", "Menlo", monospace';

  // ---------- math ----------
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, k) => a + (b - a) * k;
  const lerp2 = (p, q, k) => [lerp(p[0], q[0], k), lerp(p[1], q[1], k)];
  const inv = (a, b, v) => clamp((v - a) / (b - a));
  const ease = {
    out: k => 1 - Math.pow(1 - k, 3),
    in: k => k * k * k,
    inOut: k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2),
    back: k => 1 + 2.2 * Math.pow(k - 1, 3) + 1.2 * Math.pow(k - 1, 2),
  };
  const rot = (v, deg) => {
    const r = (deg * Math.PI) / 180, c = Math.cos(r), s = Math.sin(r);
    return [v[0] * c - v[1] * s, v[0] * s + v[1] * c];
  };
  const add = (a, b) => [a[0] + b[0], a[1] + b[1]];

  // Punch extension curve for local progress p in [0,1]: fast out, short hold, slower return.
  function punchCurve(p) {
    if (p <= 0 || p >= 1) return 0;
    if (p < 0.3) return ease.out(p / 0.3);
    if (p < 0.45) return 1;
    return 1 - ease.inOut((p - 0.45) / 0.55);
  }
  // Progress of a punch that starts at t0 and lasts dur.
  const punchAt = (t, t0, dur = 0.42) => punchCurve((t - t0) / dur);

  // Two-bone IK. Returns [joint, end]. bend = +1/-1 picks the side of the joint.
  function ik(root, target, l1, l2, bend) {
    const dx = target[0] - root[0], dy = target[1] - root[1];
    let d = Math.hypot(dx, dy);
    const a = Math.atan2(dy, dx);
    const maxD = l1 + l2 - 0.001;
    if (d > maxD) d = maxD;
    const cosA = clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1);
    const ang = a + bend * Math.acos(cosA);
    const joint = [root[0] + l1 * Math.cos(ang), root[1] + l1 * Math.sin(ang)];
    const end = [root[0] + d * Math.cos(a), root[1] + d * Math.sin(a)];
    return [joint, end];
  }

  // ---------- figure ----------
  // Local coordinates: facing right, y up, ground at 0, total height ~100 units.
  const GUARD_LEAD = [12, 5], GUARD_REAR = [7, 10];
  const REACH = 31;
  function basePose() {
    return {
      hip: [0, 46], lean: 6, headDx: 0, headDy: 0,
      front: [18, 0], back: [-19, 0],
      lead: GUARD_LEAD.slice(), rear: GUARD_REAR.slice(),
    };
  }
  // Apply punches. Each entry: {type:'jab'|'cross'|'hook'|'rhook'|'upper'|'rupper', k: 0..1}
  function applyPunches(pose, punches) {
    for (const { type, k } of punches) {
      if (k <= 0) continue;
      if (type === 'jab') {
        pose.lead = lerp2(pose.lead, [REACH + 1, 4], k);
        pose.lean += 5 * k; pose.hip[0] += 2 * k;
      } else if (type === 'cross') {
        pose.rear = lerp2(pose.rear, [REACH + 4, 4], k);
        pose.lean += 12 * k; pose.hip[0] += 4 * k; pose.lead = lerp2(pose.lead, [8, 9], k);
      } else if (type === 'hook') {
        // Lead hook: elbow up, hand travels across at head height.
        const arc = [lerp(6, 22, k), 4 + Math.sin(k * Math.PI) * 4];
        pose.lead = lerp2(pose.lead, arc, Math.min(1, k * 1.6));
        pose.lean += 4 * k; pose.hip[0] -= 1 * k;
      } else if (type === 'rhook') {
        pose.rear = lerp2(pose.rear, [24, 5], k);
        pose.lean += 9 * k; pose.hip[0] += 3 * k;
      } else if (type === 'upper') {
        const path = k < 0.4 ? lerp2(pose.lead, [12, -10], k / 0.4) : lerp2([12, -10], [19, 9], (k - 0.4) / 0.6);
        pose.lead = path; pose.hip[1] -= 3 * Math.sin(k * Math.PI); pose.lean += 3 * k;
      } else if (type === 'rupper') {
        const path = k < 0.4 ? lerp2(pose.rear, [10, -12], k / 0.4) : lerp2([10, -12], [21, 8], (k - 0.4) / 0.6);
        pose.rear = path; pose.hip[1] -= 3 * Math.sin(k * Math.PI); pose.lean += 8 * k; pose.hip[0] += 2 * k;
      }
    }
    return pose;
  }

  // Draw a boxer. f = {x, ground, s (px/unit), facing (+1 right,-1 left), hero:bool, alpha, pose, glow:{part,color,k}}
  function drawFigure(ctx, f) {
    const p = f.pose || basePose();
    const s = f.s, dir = f.facing || 1;
    const P = v => [f.x + dir * v[0] * s, f.ground - v[1] * s];
    const col = f.hero
      ? { body: C.hero, limb: C.heroLimb, back: C.heroBack }
      : { body: C.opp, limb: C.oppLimb, back: C.oppBack };
    const shoulder = add(p.hip, rot([0, 30], -p.lean));
    const neck = add(p.hip, rot([0, 33], -p.lean));
    const head = add(neck, rot([2.5 + p.headDx, 9.5 + p.headDy], -p.lean * 0.6));
    const leadSh = add(shoulder, [2.5, 0]), rearSh = add(shoulder, [-2.5, -0.5]);
    const leadT = add(shoulder, p.lead), rearT = add(shoulder, p.rear);
    // IK in local space; leg knees bend forward (bend sign depends on side), elbows bend down.
    const leg = foot => ik(p.hip, foot, 25.5, 25.5, foot[0] >= p.hip[0] ? 1 : 1);
    const [fk, ff] = leg(p.front), [bk, bf] = leg(p.back);
    const [le, lh] = ik(leadSh, leadT, 15.5, 15.5, -1);
    const [re, rh] = ik(rearSh, rearT, 15.5, 15.5, -1);

    ctx.save();
    ctx.globalAlpha = f.alpha == null ? 1 : f.alpha;
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const seg = (pts, w, color) => {
      ctx.strokeStyle = color; ctx.lineWidth = w * s; ctx.beginPath();
      const q = pts.map(P); ctx.moveTo(q[0][0], q[0][1]);
      for (let i = 1; i < q.length; i++) ctx.lineTo(q[i][0], q[i][1]);
      ctx.stroke();
    };
    const glove = (pt, r, color) => {
      const q = P(pt); ctx.fillStyle = color; ctx.beginPath(); ctx.arc(q[0], q[1], r * s, 0, Math.PI * 2); ctx.fill();
    };
    const gloveCol = f.hero ? C.red : (f.oppGloves || '#6b7079');
    const gloveBack = f.hero ? '#b8261f' : '#555a62';

    // shadow
    const sh = P([0, 0]);
    ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.beginPath();
    ctx.ellipse(sh[0], sh[1] + 4, 30 * s, 4 * s, 0, 0, Math.PI * 2); ctx.fill();

    // back limbs
    seg([p.hip, bk, bf], 7, col.back);
    seg([bf, add(bf, [-5, 0])], 5, col.back);
    seg([rearSh, re, rh], 6.2, col.back);
    glove(rh, 5.6, gloveBack);
    // torso
    seg([p.hip, shoulder], 15, col.body);
    ctx.fillStyle = col.body;
    const hq = P(head); ctx.beginPath(); ctx.arc(hq[0], hq[1], 8.2 * s, 0, Math.PI * 2); ctx.fill();
    seg([neck, add(neck, [0.5, 3])], 6, col.body);
    // front limbs
    seg([p.hip, fk, ff], 7, col.limb);
    seg([ff, add(ff, [5, 0])], 5, col.limb);
    seg([leadSh, le, lh], 6.2, col.limb);
    glove(lh, 5.8, gloveCol);
    // rear glove drawn in front when guarding the chin
    if (rh[0] > shoulder[0] + 4) glove(rh, 5.6, gloveCol);

    if (f.glow) {
      const pts = { lead: lh, rear: rh, head, chest: shoulder, hip: p.hip }[f.glow.part];
      if (pts) {
        const q = P(pts); const r = (f.glow.r || 14) * s;
        const g = ctx.createRadialGradient(q[0], q[1], 0, q[0], q[1], r);
        g.addColorStop(0, hexA(f.glow.color, 0.75 * f.glow.k)); g.addColorStop(1, hexA(f.glow.color, 0));
        ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(q[0], q[1], r, 0, Math.PI * 2); ctx.fill();
        ctx.globalCompositeOperation = 'source-over';
      }
    }
    ctx.restore();
    return { lead: P(lh), rear: P(rh), head: P(head), headR: 8.2 * s, chest: P(shoulder), hip: P(p.hip), toWorld: P };
  }

  function hexA(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${clamp(a)})`;
  }

  // ---------- stage ----------
  function background(ctx, t, opts = {}) {
    ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
    const g = ctx.createRadialGradient(W / 2, H * 0.62, 50, W / 2, H * 0.62, H * 0.75);
    g.addColorStop(0, '#202329'); g.addColorStop(1, C.bg);
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    if (opts.ropes !== false) {
      // ring ropes receding
      ctx.lineWidth = 3;
      [[860, 830], [960, 940], [1060, 1050]].forEach(([y1, y2], i) => {
        ctx.strokeStyle = hexA(C.red, 0.28 - i * 0.05);
        ctx.beginPath(); ctx.moveTo(-20, y1); ctx.lineTo(W + 20, y2); ctx.stroke();
      });
    }
    // floor
    const fy = opts.ground || 1480;
    const fg = ctx.createLinearGradient(0, fy - 40, 0, H);
    fg.addColorStop(0, 'rgba(255,255,255,0.035)'); fg.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = fg; ctx.fillRect(0, fy - 40, W, H - fy + 40);
    ctx.strokeStyle = 'rgba(255,255,255,0.06)'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(0, fy + 6); ctx.lineTo(W, fy + 6); ctx.stroke();
  }

  // Film grain + vignette for a less "flat vector" look.
  function finish(ctx, t) {
    const v = ctx.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 0.8);
    v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,0,0.55)');
    ctx.fillStyle = v; ctx.fillRect(0, 0, W, H);
  }

  // Headline: eyebrow + two lines, second line red. Lines wipe up in sequence from `t0`.
  function headline(ctx, t, t0, { eyebrow, l1, l2, size = 128, y = 250, out = Infinity, red2 = true, x = 70 }) {
    const lt = t - t0;
    if (lt < 0 || t >= out) return;
    const fadeOut = out === Infinity ? 1 : 1 - inv(out - 0.16, out, t);
    ctx.save();
    ctx.globalAlpha = fadeOut;
    if (eyebrow) {
      const k = ease.out(inv(0, 0.25, lt));
      ctx.globalAlpha = fadeOut * k;
      ctx.fillStyle = C.red; ctx.fillRect(x, y - size * 0.95 - 28, 12, 12);
      ctx.font = `600 26px ${MONO_FONT}`; ctx.fillStyle = C.mono; ctx.textBaseline = 'middle';
      ctx.fillText(eyebrow.toUpperCase().split('').join(String.fromCharCode(8202)), x + 26, y - size * 0.95 - 22);
      ctx.globalAlpha = fadeOut;
    }
    ctx.font = `bold ${size}px ${HEAD_FONT}`; ctx.textBaseline = 'alphabetic';
    const line = (txt, i, color) => {
      if (!txt) return;
      const k = ease.out(inv(i * 0.09, i * 0.09 + 0.22, lt));
      const yy = y + i * size * 0.88;
      ctx.save();
      ctx.beginPath(); ctx.rect(0, yy - size * 0.85, W, size * 0.95); ctx.clip();
      ctx.fillStyle = color;
      ctx.fillText(txt, x, yy + (1 - k) * size * 0.9);
      ctx.restore();
    };
    line(l1, 0, C.text);
    line(l2, 1, red2 ? C.red : C.text);
    ctx.restore();
  }

  function label(ctx, txt, x, y, { color = C.red, size = 30, align = 'center', alpha = 1, font = MONO_FONT, weight = 700 } = {}) {
    ctx.save(); ctx.globalAlpha = alpha; ctx.fillStyle = color; ctx.font = `${weight} ${size}px ${font}`;
    ctx.textAlign = align; ctx.textBaseline = 'middle'; ctx.fillText(txt, x, y); ctx.restore();
  }

  function pill(ctx, txt, x, y, { bg = C.red, color = '#fff', size = 28, alpha = 1 } = {}) {
    ctx.save(); ctx.globalAlpha = alpha; ctx.font = `700 ${size}px ${MONO_FONT}`;
    const w = ctx.measureText(txt).width + size * 1.4, h = size * 1.7;
    ctx.fillStyle = bg; roundRect(ctx, x - w / 2, y - h / 2, w, h, h / 2); ctx.fill();
    ctx.fillStyle = color; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(txt, x, y + 1);
    ctx.restore();
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }

  // HUD frame (the red corner brackets used in the app-analysis segments).
  function hudFrame(ctx, x, y, w, h, alpha = 1, caption) {
    ctx.save(); ctx.globalAlpha = alpha; ctx.strokeStyle = C.red; ctx.lineWidth = 4;
    const c = 44;
    [[x, y, 1, 1], [x + w, y, -1, 1], [x, y + h, 1, -1], [x + w, y + h, -1, -1]].forEach(([px, py, sx, sy]) => {
      ctx.beginPath(); ctx.moveTo(px + sx * c, py); ctx.lineTo(px, py); ctx.lineTo(px, py + sy * c); ctx.stroke();
    });
    if (caption) label(ctx, caption, x + 24, y + 30, { size: 22, align: 'left', color: C.red });
    ctx.restore();
  }

  function impact(ctx, x, y, k, color = '#fff', r = 90) {
    if (k <= 0 || k >= 1) return;
    ctx.save(); ctx.strokeStyle = hexA(color, 1 - k); ctx.lineWidth = 8 * (1 - k);
    ctx.beginPath(); ctx.arc(x, y, r * ease.out(k), 0, Math.PI * 2); ctx.stroke();
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2, r1 = r * 0.6 * ease.out(k), r2 = r * 1.15 * ease.out(k);
      ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * r1, y + Math.sin(a) * r1); ctx.lineTo(x + Math.cos(a) * r2, y + Math.sin(a) * r2); ctx.stroke();
    }
    ctx.restore();
  }

  // Simple camera: zoom about a point.
  function camera(ctx, zoom, cx, cy) {
    ctx.translate(cx, cy); ctx.scale(zoom, zoom); ctx.translate(-cx, -cy);
  }

  // Closing comment prompt, no branding (CTA-free phase).
  function questionCard(ctx, t, t0, { eyebrow = 'YOUR TURN', question }) {
    const k = ease.out(inv(t0, t0 + 0.35, t));
    if (k <= 0) return;
    ctx.save();
    ctx.fillStyle = hexA('#0d0e10', 0.82 * k); ctx.fillRect(0, 0, W, H);
    ctx.globalAlpha = k;
    const y0 = 860 + (1 - k) * 40;
    label(ctx, eyebrow, W / 2, y0 - 120, { size: 28, color: C.mono });
    ctx.font = `bold 150px ${HEAD_FONT}`; ctx.textAlign = 'center';
    question.forEach((ln, i) => { ctx.fillStyle = i === question.length - 1 ? C.red : C.text; ctx.fillText(ln, W / 2, y0 + i * 132); });
    label(ctx, 'COMMENT  ↓', W / 2, y0 + question.length * 132 + 10, { size: 30, color: C.dim });
    ctx.restore();
  }

  function endCard(ctx, t, t0, { question, sub = 'YOUR BOXING COACH · LINK IN BIO' }) {
    const k = ease.out(inv(t0, t0 + 0.4, t));
    if (k <= 0) return;
    ctx.save();
    ctx.fillStyle = hexA('#0d0e10', 0.88 * k); ctx.fillRect(0, 0, W, H);
    ctx.globalAlpha = k;
    const cy = 820 + (1 - k) * 40;
    // app icon
    ctx.fillStyle = '#1b1d21'; roundRect(ctx, W / 2 - 110, cy - 300, 220, 220, 52); ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = C.red; ctx.beginPath(); ctx.arc(W / 2 - 22, cy - 190, 34, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(W / 2 + 26, cy - 176, 30, 0, Math.PI * 2); ctx.fill();
    ctx.font = `bold 170px ${HEAD_FONT}`; ctx.fillStyle = C.text; ctx.textAlign = 'center';
    ctx.fillText('BOX', W / 2, cy + 110);
    label(ctx, sub, W / 2, cy + 160, { size: 24, color: C.dim });
    if (question) {
      ctx.font = `bold 92px ${HEAD_FONT}`; ctx.textAlign = 'center';
      question.forEach((ln, i) => { ctx.fillStyle = i === question.length - 1 ? C.red : C.text; ctx.fillText(ln, W / 2, cy + 340 + i * 88); });
    }
    ctx.restore();
  }

  window.BOX = {
    W, H, C, HEAD_FONT, MONO_FONT, clamp, lerp, lerp2, inv, ease, rot, add, punchAt, punchCurve,
    basePose, applyPunches, drawFigure, background, finish, headline, label, pill, hudFrame, impact,
    camera, endCard, questionCard, roundRect, hexA, GUARD_LEAD, GUARD_REAR, REACH,
  };
})();
