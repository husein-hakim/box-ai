"""Kokoro voiceover for a scene.

  .venv/bin/python voiceover.py <scene>             # builds out/<scene>_vo.wav and out/<scene>_final.mp4
  .venv/bin/python voiceover.py --samples "text"    # one clip per candidate voice in out/voice-samples/

Reads videos/<scene>.vo.json: {"voice": "am_michael", "speed": 1.0, "lines": [{"t": 0.0, "text": "..."}]}
Each line starts at its "t" (the scene's beat time). A line that would overlap the previous one is pushed
later and reported, so the scene timing can be adjusted to match.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro import KPipeline

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
SR = 24000
GAP = 0.18
CANDIDATES = ["am_michael", "am_fenrir", "am_puck", "am_echo", "am_onyx", "bm_george", "bm_fable"]

_pipes = {}


def synth(text, voice, speed):
    lang = voice[0]  # 'a' American, 'b' British
    if lang not in _pipes:
        _pipes[lang] = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M")
    chunks = [a.numpy() if hasattr(a, "numpy") else a for _, _, a in _pipes[lang](text, voice=voice, speed=speed)]
    audio = np.concatenate(chunks)
    # trim leading/trailing silence so beats land on the cut
    idx = np.where(np.abs(audio) > 0.01)[0]
    return audio[max(0, idx[0] - 240): idx[-1] + 2400] if len(idx) else audio


def samples(text):
    d = OUT / "voice-samples"
    d.mkdir(parents=True, exist_ok=True)
    for v in CANDIDATES:
        sf.write(d / f"{v}.wav", synth(text, v, 1.0), SR)
        print(d / f"{v}.wav")


def build(scene):
    spec = json.loads((ROOT / "videos" / f"{scene}.vo.json").read_text())
    voice, speed = spec.get("voice", "am_michael"), spec.get("speed", 1.0)
    placed, cursor = [], 0.0
    print(f"{'want':>6} {'start':>6} {'end':>6}  line")
    for i, line in enumerate(spec["lines"]):
        audio = synth(line["text"], voice, line.get("speed", speed))
        start = max(line["t"], cursor + (GAP if i else 0))
        end = start + len(audio) / SR
        nxt = spec["lines"][i + 1]["t"] if i + 1 < len(spec["lines"]) else spec.get("end", end)
        flag = "  <-- pushed" if start > line["t"] + 0.01 else ""
        flag += f"  <-- overruns next beat by {end - nxt:.2f}s" if end > nxt else ""
        print(f"{line['t']:6.2f} {start:6.2f} {end:6.2f}  {line['text']}{flag}")
        placed.append((start, audio))
        cursor = end
    total = max(spec.get("end", 0), cursor + 0.5)
    mix = np.zeros(int(total * SR), dtype=np.float32)
    for start, audio in placed:
        s = int(start * SR)
        mix[s: s + len(audio)] += audio
    mix /= max(1.0, np.abs(mix).max() / 0.95)
    OUT.mkdir(exist_ok=True)
    wav = OUT / f"{scene}_vo.wav"
    sf.write(wav, mix, SR)
    video = OUT / f"{scene}.mp4"
    if video.exists():
        final = OUT / f"{scene}_final.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-i", str(wav),
                        "-filter_complex", "[1:a]apad,loudnorm=I=-14:TP=-1.5:LRA=11[a]",
                        "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                        "-shortest", str(final)], check=True)
        print(final)


if __name__ == "__main__":
    if sys.argv[1] == "--samples":
        samples(sys.argv[2])
    else:
        build(sys.argv[1])
