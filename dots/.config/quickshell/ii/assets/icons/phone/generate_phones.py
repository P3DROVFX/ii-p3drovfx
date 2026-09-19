#!/usr/bin/env python3
"""Render the phone-*.png device icons in this folder from phones.json.

Front view on the 64-grid of the MacOS-Like device icons: body scaled from the real
dimensions in mm, frame in the model's launch colour, black bezel, grey screen gradient,
4 dock tiles and a gesture bar. Needs only python3 and rsvg-convert.

    ./generate_phones.py                 # every model in phones.json
    ./generate_phones.py galaxy-s24      # only slugs containing the string
    ./generate_phones.py --svg           # also keep the .svg next to each .png

It also writes index.json: {marketing name: file}, i.e. the name KDE Connect reports.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SIZE_PX = 512

CORNER = {"square": 1.0, "rounded": 3.6, "very-rounded": 5.4}
BEZEL = {"thin": .6, "medium": 1.0, "thick": 1.6}
RIM = .6  # visible metal frame around the black glass

# Fallback for phones that have no entry of their own
GENERIC = {
    "slug": "generic-android", "name": "Android phone", "year": 0,
    "height_mm": 160.0, "width_mm": 75.0, "form": "bar", "corner": "rounded",
    "bezel": "thin", "camera": "hole-center", "notch_width_frac": None,
    "buttons": [{"side": "right", "kind": "volume-rocker", "start": .22, "length": .12},
                {"side": "right", "kind": "power", "start": .37, "length": .06}],
    "home_button": False, "spen": False, "frame_hex": "#8a8a8a", "notes": "",
}


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def shade(hex_colour, k):
    """k > 0 mixes towards white, k < 0 towards black."""
    h = hex_colour.lstrip("#")
    rgb = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    target = 255 if k > 0 else 0
    rgb = [round(c + (target - c) * abs(k)) for c in rgb]
    return "#" + "".join(f"{c:02x}" for c in rgb)


def body_size(p):
    hmm, wmm = p["height_mm"], p["width_mm"]
    h, w = 56.0, 56.0 * wmm / hmm
    if w > 54.0:  # unfolded book foldables are nearly square
        h, w = 54.0 * hmm / wmm, 54.0
    return w, h


def build(p):
    W, H = body_size(p)
    x, y = 32 - W / 2, 32 - H / 2
    rad = CORNER.get(p["corner"], 3.6)
    form, cam = p["form"], p["camera"]
    home = p.get("home_button", False)
    notes = (p.get("notes") or "").lower()
    frame = p.get("frame_hex") or "#8a8a8a"
    dark = shade(frame, -.45)

    side_b = top_b = bot_b = BEZEL.get(p["bezel"], .6)
    if home:
        side_b, top_b, bot_b = 1.6, 6.5, 6.5
    elif cam == "bezel":
        top_b, bot_b = max(top_b, 2.2), max(bot_b, 1.6)
        if form == "book-fold":
            side_b = max(side_b, 1.4)

    out = []

    # Buttons first so the frame covers their inner half
    for b in p.get("buttons", []):
        start, length = float(b["start"]), max(float(b["length"]), .03)
        if b["side"] == "left":
            out.append(f'<rect width="1.2" height="{f(length * H)}" x="{f(x - .6)}" '
                       f'y="{f(y + start * H)}" rx=".5" fill="{dark}"/>')
        elif b["side"] == "right":
            out.append(f'<rect width="1.2" height="{f(length * H)}" x="{f(x + W - .6)}" '
                       f'y="{f(y + start * H)}" rx=".5" fill="{dark}"/>')
        else:  # top: start/length are fractions of the width
            out.append(f'<rect width="{f(length * W)}" height="1.2" x="{f(x + start * W)}" '
                       f'y="{f(y - .6)}" rx=".5" fill="{dark}"/>')

    out.append(f'<rect width="{f(W)}" height="{f(H)}" x="{f(x)}" y="{f(y)}" rx="{f(rad)}" '
               f'fill="url(#frame)"/>')
    out.append(f'<rect width="{f(W - 2 * RIM)}" height="{f(H - 2 * RIM)}" x="{f(x + RIM)}" '
               f'y="{f(y + RIM)}" rx="{f(max(rad - RIM, .6 if rad > 1 else .5))}" fill="#000"/>')

    sx, sy = x + RIM + side_b, y + RIM + top_b
    sw, sh = W - 2 * (RIM + side_b), H - 2 * RIM - top_b - bot_b
    srad = .4 if home or cam == "bezel" else max(rad - RIM - side_b, .4)
    out.append(f'<rect width="{f(sw)}" height="{f(sh)}" x="{f(sx)}" y="{f(sy)}" rx="{f(srad)}" '
               f'fill="url(#screen)"/>')

    # Curved screens: a faint sheen down both long edges
    if "curved" in notes or "endless" in notes or "waterfall" in notes:
        for ex in (sx, sx + sw - 1.1):
            out.append(f'<rect width="1.1" height="{f(sh - 2 * srad)}" x="{f(ex)}" '
                       f'y="{f(sy + srad)}" style="opacity:.14;fill:#fff"/>')

    # Camera
    hole_r = .55 if p["bezel"] == "thin" else .7
    if cam.startswith("hole"):
        frac = {"hole-left": .12, "hole-right": .88}.get(cam, .5)
        if form == "book-fold" and cam == "hole-center":
            frac = .75  # inner-screen punch hole sits on the right panel
        cx, cy = sx + sw * frac, sy + .55 + hole_r
        out.append(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(hole_r)}" fill="#000"/>')
        out.append(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(hole_r * .4)}" fill="#1c2a3a"/>')
    elif cam in ("island", "pill-center"):
        iw = min(10.0, sw * .38)
        out.append(f'<rect width="{f(iw)}" height="2.5" x="{f(32 - iw / 2)}" y="{f(sy + .9)}" '
                   f'rx="1.25" fill="#000"/>')
    elif cam == "notch":
        nw = sw * (p.get("notch_width_frac") or .3)
        if nw > 5:  # wide iPhone-style notch
            out.append(f'<rect width="{f(nw)}" height="2.6" x="{f(32 - nw / 2)}" y="{f(sy - .5)}" '
                       f'rx="1" fill="#000"/>')
        else:  # waterdrop / U notch
            out.append(f'<rect width="{f(max(nw, 2.4))}" height="2" x="{f(32 - max(nw, 2.4) / 2)}" '
                       f'y="{f(sy - .8)}" rx="1.2" fill="#000"/>')
    elif cam == "bezel":
        cy = y + RIM + top_b / 2
        if home:
            out.append(f'<circle cx="27" cy="{f(cy)}" r=".7" fill="#1a1a1a"/>')
            out.append(f'<rect width="7" height="1" x="28.5" y="{f(cy - .5)}" rx=".5" fill="#2a2a2a"/>')
        elif form == "book-fold":
            out.append(f'<circle cx="{f(sx + sw * .82)}" cy="{f(cy)}" r=".55" fill="#1c2a3a"/>')
        else:
            out.append(f'<circle cx="36" cy="{f(cy)}" r=".55" fill="#1c2a3a"/>')
            out.append(f'<rect width="7" height=".7" x="28.5" y="{f(cy - .35)}" rx=".35" fill="#2a2a2a"/>')
    elif cam == "under-display":
        cx = sx + sw * (.75 if form == "book-fold" else .5)
        out.append(f'<circle cx="{f(cx)}" cy="{f(sy + 1.2)}" r=".6" style="opacity:.12;fill:#000"/>')

    if form == "book-fold":
        out.append(f'<rect width=".5" height="{f(sh)}" x="31.75" y="{f(sy)}" style="opacity:.18;fill:#fff"/>')
    elif form == "flip":
        out.append(f'<rect width="{f(sw)}" height=".5" x="{f(sx)}" y="{f(sy + sh / 2 - .25)}" '
                   f'style="opacity:.18;fill:#fff"/>')

    # Dock: icons shrink so the row keeps 1.5 of margin, gap = half an icon
    n = 4 if sw < 34 else 7
    s = min(4.0, (sw - 3) / (1.5 * n - .5))
    gap = s / 2
    ix = 32 - (n * s + (n - 1) * gap) / 2
    iy = sy + sh - (2.5 if home else 5.3) - s
    for i in range(n):
        out.append(f'<rect width="{f(s)}" height="{f(s)}" x="{f(ix + i * (s + gap))}" y="{f(iy)}" '
                   f'rx="{f(s / 4)}" style="opacity:.35;fill:#fff"/>')
    if home:
        out.append(f'<circle cx="32" cy="{f(y + H - RIM - bot_b / 2)}" r="2.3" fill="none" '
                   f'stroke="#3a3a3a" stroke-width=".5"/>')
    else:
        bw = min(9.0, sw * .36)
        out.append(f'<rect width="{f(bw)}" height=".9" x="{f(32 - bw / 2)}" y="{f(sy + sh - 2.5)}" '
                   f'rx=".45" fill="#a5a5a5"/>')

    if p.get("spen"):
        out.append(f'<rect width="3.2" height=".7" x="{f(x + 2.2)}" y="{f(y + H - .7)}" rx=".35" '
                   f'fill="#1e1e1e"/>')

    defs = (f'<linearGradient id="frame" x1="{f(x)}" x2="{f(x + W)}" y1="{f(y)}" y2="{f(y + H)}" '
            f'gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{shade(frame, .15)}"/>'
            f'<stop offset=".5" stop-color="{frame}"/>'
            f'<stop offset="1" stop-color="{shade(frame, -.35)}"/></linearGradient>'
            f'<linearGradient id="screen" x1="32" x2="32" y1="{f(sy + sh)}" y2="{f(sy)}" '
            f'gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#353535"/>'
            f'<stop offset="1" stop-color="#979797"/></linearGradient>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs>' + defs
            + "</defs>" + "".join(out) + "</svg>\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    keep_svg = "--svg" in sys.argv
    phones = json.loads((HERE / "phones.json").read_text()) + [GENERIC]
    index = {}
    done = 0
    for p in phones:
        name = f"phone-{p['slug']}"
        index[p["name"]] = f"{name}.png"
        if args and not any(a in p["slug"] for a in args):
            continue
        svg = build(p)
        if keep_svg:
            (HERE / f"{name}.svg").write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(SIZE_PX), "-o", str(HERE / f"{name}.png")],
                       input=svg.encode(), check=True)
        done += 1
    (HERE / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    print(f"{done} icons written, {len(index)} names in index.json")


if __name__ == "__main__":
    main()
