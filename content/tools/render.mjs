// Usage: node render.mjs <scene> [--from s --to s --fps 30 --stills t1,t2,...]
// Renders content/videos/<scene>.js to content/out/<scene>.mp4 (1080x1920, H.264).
import puppeteer from 'puppeteer-core';
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const scene = args[0];
const opt = k => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : undefined; };
const fps = Number(opt('fps') || 30);
const outDir = path.resolve(here, '../out'); mkdirSync(outDir, { recursive: true });

const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true, args: ['--allow-file-access-from-files'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1080, height: 1920 });
await page.goto('file://' + path.join(here, 'player.html') + '?scene=' + scene);
await page.waitForFunction('window.sceneReady === true');
await page.evaluate(() => document.fonts.ready);
const duration = await page.evaluate(() => window.SCENE.duration);
const grab = t => page.evaluate(t => { window.renderAt(t); return document.getElementById('c').toDataURL('image/jpeg', 0.93).split(',')[1]; }, t);

if (opt('stills')) {
  for (const t of opt('stills').split(',').map(Number)) {
    writeFileSync(path.join(outDir, `${scene}_${t.toFixed(2)}.jpg`), Buffer.from(await grab(t), 'base64'));
  }
  await browser.close(); process.exit(0);
}

const from = Number(opt('from') || 0), to = Number(opt('to') || duration);
const out = path.join(outDir, `${scene}.mp4`);
const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(fps), '-i', '-',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'medium', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
const n = Math.round((to - from) * fps);
for (let i = 0; i < n; i++) {
  const buf = Buffer.from(await grab(from + i / fps), 'base64');
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 60 === 0) process.stdout.write(`\r${scene}: ${i}/${n}`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log(`\n${out}`);
