"""Generate gap-filler slideshow photos with fal. Use it only for shots Pinterest doesn't have.

  .venv/bin/python fal_images.py "boxer wrapping hands on a bench in a dark gym" --name hand-wraps --n 2
  .venv/bin/python fal_images.py ... --model fal-ai/flux-pro/v1.1-ultra

Needs FAL_KEY in the environment or in the repo's .env (gitignored). Images land in
slideshows/library/ai/<name>-<n>.jpg. The style suffix keeps them in the candid, moody, faceless look
of the reference slideshows.
"""
import argparse
import json
import os
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "slideshows" / "library" / "ai"
STYLE = ("candid amateur iPhone photo, moody low light, deep shadows, cinematic, natural film grain, "
         "subject faceless or turned away from camera, no text, no logos, vertical composition")


def fal_key():
    if os.environ.get("FAL_KEY"):
        return os.environ["FAL_KEY"]
    env = ROOT.parent / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("FAL_KEY="):
                return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("FAL_KEY not set: add FAL_KEY=... to /Users/husein/Documents/box/.env")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("--name", required=True)
    ap.add_argument("--n", type=int, default=2)
    ap.add_argument("--model", default="fal-ai/flux-pro/v1.1-ultra")
    a = ap.parse_args()
    body = {"prompt": f"{a.prompt}. {STYLE}", "num_images": a.n, "aspect_ratio": "9:16",
            "raw": True, "output_format": "jpeg", "enable_safety_checker": True}
    req = urllib.request.Request(f"https://fal.run/{a.model}", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Key {fal_key()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        res = json.load(r)
    LIB.mkdir(parents=True, exist_ok=True)
    start = len(list(LIB.glob(f"{a.name}-*.jpg")))
    for i, im in enumerate(res.get("images", []), start + 1):
        dest = LIB / f"{a.name}-{i}.jpg"
        urllib.request.urlretrieve(im["url"], dest)
        print(dest)


if __name__ == "__main__":
    main()
