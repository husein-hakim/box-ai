"""Render TikTok photo-mode slideshows.

  .venv/bin/python slides.py <id> [<id> ...]     # e.g. slides.py 1A 1B
  .venv/bin/python slides.py --all

Reads slideshows/<id>.json and writes out/slideshows/<id>/1.jpg … plus preview.jpg (contact sheet).
Text is set in TikTok Sans, Title Case, white with a black outline (TikTok's outlined "Classic" text), so it reads like
text typed in the TikTok editor. A slide whose image is missing renders a grey placeholder that lists
the image it needs.
"""
import json
import sys
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "slideshows"
LIB = SPECS / "library"
OUT = ROOT / "out" / "slideshows"
FONT = Path(__file__).resolve().parent / "fonts" / "TikTokSans.ttf"
W, H = 1080, 1920
TEXT_W = 780          # keep clear of TikTok's right-hand button rail
TEXT_SIZE = 68
SUB_SIZE = 64
WEIGHT = 560          # TikTok "Classic" sits between Medium and SemiBold
STROKE = 4            # black outline, as in TikTok's outlined text style


def font(size, weight=WEIGHT):
    f = ImageFont.truetype(str(FONT), size)
    if isinstance(weight, str):
        f.set_variation_by_name(weight)
    else:
        f.set_variation_by_axes([36, 100, weight, 0])  # opsz, wdth, wght, slnt
    return f


def title_case(text):
    """Capitalise each word's first letter, TikTok-caption style, leaving the rest untouched."""
    out = []
    for w in text.split(" "):
        i = 0
        while i < len(w) and not w[i].isalnum():
            i += 1
        out.append(w[:i] + w[i:i + 1].upper() + w[i + 1:])
    return " ".join(out)


def smart_quotes(text):
    return text.replace("'", "\u2019")


def wrap(draw, text, fnt, max_w):
    """Greedy wrap, then narrow the column as far as possible without adding a line, so no word is left alone."""
    lines = _greedy(draw, text, fnt, max_w)
    lo, hi = max_w * 0.4, max_w
    while hi - lo > 4:
        mid = (lo + hi) / 2
        if len(_greedy(draw, text, fnt, mid)) <= len(lines):
            hi = mid
        else:
            lo = mid
    return _greedy(draw, text, fnt, hi)


def _greedy(draw, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        test = f"{cur} {w}".strip()
        if draw.textlength(test, font=fnt) <= max_w:
            cur = test
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def background(slide):
    path = LIB / slide["image"] if slide.get("image") else None
    if path and path.exists():
        img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        img = ImageOps.fit(img, (W, H), Image.LANCZOS, centering=tuple(slide.get("focus", (0.5, 0.5))))
        return ImageEnhance.Brightness(img).enhance(slide.get("brightness", 0.92))
    img = Image.new("RGB", (W, H), (38, 40, 44))
    d = ImageDraw.Draw(img)
    hint = slide.get("needs", "")
    if slide.get("image"):
        hint = f"missing file {slide['image']} — {hint}"
    d.text((60, 120), "NEEDS IMAGE", font=font(40, "Bold"), fill=(230, 80, 70))
    for i, ln in enumerate(textwrap.wrap(hint, 38)):
        d.text((60, 180 + i * 46), ln, font=font(34, "Regular"), fill=(170, 170, 170))
    return img


def draw_block(img, lines_by_style, center_y):
    """lines_by_style: list of (lines, font, gap_after). Draws centred white text with a black outline."""
    d = ImageDraw.Draw(img)
    total = sum(int(f.size * 1.2) * len(ls) + gap for ls, f, gap in lines_by_style)
    y = int(center_y - total / 2)
    for lines, fnt, gap in lines_by_style:
        lh = int(fnt.size * 1.2)
        for ln in lines:
            x = (W - d.textlength(ln, font=fnt)) / 2 - 20
            d.text((x, y), ln, font=fnt, fill=(255, 255, 255), stroke_width=STROKE, stroke_fill=(0, 0, 0))
            y += lh
        y += gap


def render(spec_id):
    spec = json.loads((SPECS / f"{spec_id}.json").read_text())
    out = OUT / spec_id
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.jpg"):
        old.unlink()
    files = []
    for i, slide in enumerate(spec["slides"], 1):
        img = background(slide)
        d = ImageDraw.Draw(img)
        main = font(slide.get("size", TEXT_SIZE))
        text = smart_quotes(title_case(slide["text"]) if spec.get("title_case", True) else slide["text"])
        block = [(wrap(d, text, main, TEXT_W), main, int(TEXT_SIZE * 1.3) if slide.get("sub") else 0)]
        if slide.get("sub"):
            sub = font(SUB_SIZE)
            block.append(([title_case(slide["sub"])], sub, 0))
        draw_block(img, block, H * slide.get("y", 0.5))
        f = out / f"{i}.jpg"
        img.save(f, quality=95)
        files.append(f)
    thumbs = [Image.open(f).resize((270, 480)) for f in files]
    sheet = Image.new("RGB", (270 * len(thumbs) + 10 * (len(thumbs) - 1), 480), (0, 0, 0))
    for i, t in enumerate(thumbs):
        sheet.paste(t, (i * 280, 0))
    sheet.save(out / "preview.jpg", quality=88)
    print(out)


if __name__ == "__main__":
    ids = [p.stem for p in sorted(SPECS.glob("*.json"))] if sys.argv[1:] == ["--all"] else sys.argv[1:]
    for sid in ids:
        render(sid)
