#!/usr/bin/env python3
"""Mama Haritası maskot ikonlarını üretir (D18).

Kedi ve köpek yüzleri (tüy rengi × ifade), ikili maskot ve nokta tipi rozetleri SVG olarak
`ios/MamaKit/Sources/MamaDesign/Resources/Mascots.xcassets` içine yazılır. Çizimler yalnızca temel
SVG öğeleri (ellipse, circle, path, rect) ve sunum öznitelikleri kullanır; Xcode'un asset catalog SVG
desteğiyle sorunsuz derlenir (style bloğu, clipPath, mask, filter, text yok).

    python3 scripts/generate_mascots.py                 # asset catalog'u yeniden üret
    python3 scripts/generate_mascots.py --preview DIR   # ayrıca DIR/preview.html önizleme sayfası yaz
    python3 scripts/generate_mascots.py --app-icon DIR  # uygulama ikonu SVG'leri (1024 px PNG'ye çevrilir)

İfadeler nokta durumuna bağlanır: mama kondu → happy, mama bekliyor → hungry, diğer → neutral.
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ios/MamaKit/Sources/MamaDesign/Resources/Mascots.xcassets"

INK = "#3A2A22"       # göz, ağız (açık tüylerde)
LIGHT = "#F4EEE6"     # ağız, bıyık (koyu tüylerde)
BLUSH = "#FF8FA3"
NOSE = "#F07F9A"
TONGUE = "#FF8FA3"
MOUTH_IN = "#7B3A3F"

MOODS = ["happy", "neutral", "hungry"]

CATS = {
    "orange": dict(fur="#F8AE54", line="#DB8730", inner="#FFD0BF", stripe="#E48F33", muzzle="#FFEBD2", pattern="tabby"),
    "gray": dict(fur="#B2B8C2", line="#848B98", inner="#F9C9D2", stripe="#89909D", muzzle="#F6F6F9", pattern="tabby"),
    "white": dict(fur="#FFFDF8", line="#CDBFB0", inner="#FFC8D4", pattern=None),
    "black": dict(fur="#44444F", line="#2B2B33", inner="#8A6C78", pattern=None, dark=True),
    "calico": dict(fur="#FFFDF8", line="#CDBFB0", inner="#FFC8D4", pattern="calico", patch_a="#F8AE54", patch_b="#57484F"),
}

DOGS = {
    "cream": dict(fur="#F8D8A0", line="#D9AA5E", ear="#E6B66A", muzzle="#FFF6E3"),
    "brown": dict(fur="#C48E65", line="#93613E", ear="#9D6A43", muzzle="#F6DEC6", brows="#E7BE98"),
    "black": dict(fur="#49444E", line="#2C2830", ear="#35303A", muzzle="#D8AD80", brows="#D8AD80", dark=True),
    "spotted": dict(fur="#FFFDF8", line="#CDBFB0", ear="#BE8A5F", muzzle="#FFFDF8", patch="#D09B70"),
}


def f(value: float) -> str:
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return text if text else "0"


def ellipse(cx, cy, rx, ry, fill, extra=""):
    return f'<ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{extra}/>'


def stroke_path(d, color, width):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{f(width)}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def eyes(lx, rx, y, mood, dark, iris=None):
    """İki göz. `iris` verilirse (koyu tüy) renkli iris + gözbebeği çizilir."""
    out = []
    ink = LIGHT if dark else INK
    for x in (lx, rx):
        if mood == "happy":
            out.append(stroke_path(f"M{f(x - 6)} {f(y + 2)} Q{f(x)} {f(y - 7.5)} {f(x + 6)} {f(y + 2)}", ink, 3.2))
            continue
        big = mood == "hungry"
        w, h = (7.2, 8.6) if big else (5.4, 6.6)
        if iris:
            out.append(ellipse(x, y, w + 0.8, h + 0.6, iris))
            out.append(ellipse(x, y + 0.3, w * 0.62, h * 0.82, "#1D1B22"))
        else:
            out.append(ellipse(x, y, w, h, INK))
        out.append(f'<circle cx="{f(x - w * 0.36)}" cy="{f(y - h * 0.36)}" r="{f(2.9 if big else 2.1)}" fill="#FFFFFF"/>')
        out.append(f'<circle cx="{f(x + w * 0.34)}" cy="{f(y + h * 0.36)}" r="{f(1.5 if big else 1.0)}" fill="#FFFFFF" opacity="0.85"/>')
    if mood == "hungry":
        # Yalvaran kaşlar: iç uçlar yukarıda.
        out.append(stroke_path(f"M{f(lx - 8)} {f(y - 12.5)} L{f(lx + 3)} {f(y - 16)}", ink, 2.4))
        out.append(stroke_path(f"M{f(rx + 8)} {f(y - 12.5)} L{f(rx - 3)} {f(y - 16)}", ink, 2.4))
    return out


def blush(lx, rx, y, strong):
    opacity = "0.62" if strong else "0.45"
    return [ellipse(x, y, 7.5, 4.6, BLUSH, f' opacity="{opacity}"') for x in (lx, rx)]


def cat(coat: str, mood: str) -> list[str]:
    c = CATS[coat]
    dark = c.get("dark", False)
    ink = LIGHT if dark else INK
    line = c["line"]
    out = []

    # Kulaklar (kafanın arkasında)
    left_fur = c.get("patch_a", c["fur"])
    right_fur = c.get("patch_b", c["fur"])
    left_line = "#DB8730" if c["pattern"] == "calico" else line
    right_line = "#3B3037" if c["pattern"] == "calico" else line
    out.append(f'<path d="M22 58 C16 36 21 17 30 13 C39 13 52 26 60 40 Z" fill="{left_fur}" stroke="{left_line}" stroke-width="3" stroke-linejoin="round"/>')
    out.append(f'<path d="M98 58 C104 36 99 17 90 13 C81 13 68 26 60 40 Z" fill="{right_fur}" stroke="{right_line}" stroke-width="3" stroke-linejoin="round"/>')
    out.append(f'<path d="M28.5 47 C26 35 28.5 25.5 32.5 22.5 C38 24 44.5 31.5 49 39 Z" fill="{c["inner"]}"/>')
    out.append(f'<path d="M91.5 47 C94 35 91.5 25.5 87.5 22.5 C82 24 75.5 31.5 71 39 Z" fill="{c["inner"]}"/>')

    # Kafa
    out.append(ellipse(60, 68, 44, 36, c["fur"]))
    if c["pattern"] == "calico":
        out.append(f'<path d="M16.67 61.75 A44 36 0 0 1 52.36 32.55 C51 47 39 59 16.67 61.75 Z" fill="{c["patch_a"]}"/>')
        out.append(f'<path d="M67.64 32.55 A44 36 0 0 1 103.33 61.75 C81 59 69 47 67.64 32.55 Z" fill="{c["patch_b"]}"/>')
    if c["pattern"] == "tabby":
        s = c["stripe"]
        for d in ("M60 36 L60 47", "M50.5 37.5 L52.5 46.5", "M69.5 37.5 L67.5 46.5",
                  "M18.5 63 L27 65", "M17.5 71 L26 71", "M101.5 63 L93 65", "M102.5 71 L94 71"):
            out.append(stroke_path(d, s, 3.6))
    if c.get("muzzle"):
        out.append(ellipse(60, 85, 17, 11.5, c["muzzle"]))
    if c["pattern"] == "calico":
        arc = 'fill="none" stroke-width="3" stroke-linecap="round"'
        out.append(f'<path d="M103.33 61.75 A44 36 0 1 1 16.67 61.75" {arc} stroke="{line}"/>')
        out.append(f'<path d="M16.67 61.75 A44 36 0 0 1 52.36 32.55" {arc} stroke="{left_line}"/>')
        out.append(f'<path d="M52.36 32.55 A44 36 0 0 1 67.64 32.55" {arc} stroke="{line}"/>')
        out.append(f'<path d="M67.64 32.55 A44 36 0 0 1 103.33 61.75" {arc} stroke="{right_line}"/>')
    else:
        out.append(f'<ellipse cx="60" cy="68" rx="44" ry="36" fill="none" stroke="{line}" stroke-width="3"/>')

    # Yüz
    out += blush(29, 91, 83, mood == "happy")
    out += eyes(42, 78, 70, mood, dark, iris="#F7DC6A" if dark else None)
    out.append(f'<path d="M56.2 77.2 Q60 75.6 63.8 77.2 Q62.6 81.4 60 82 Q57.4 81.4 56.2 77.2 Z" fill="{NOSE}"/>')
    if mood == "hungry":
        out.append(ellipse(60, 88.2, 4.4, 4.8, MOUTH_IN))
        out.append(ellipse(60, 90.4, 2.9, 2.2, TONGUE))
    else:
        out.append(stroke_path("M51.5 84.5 Q55.8 89.8 60 84.5 Q64.2 89.8 68.5 84.5", ink, 2.4))
    whisker = LIGHT if dark else line
    for d in ("M23 79 L10 76.5", "M23 85 L11 87.5", "M97 79 L110 76.5", "M97 85 L109 87.5"):
        out.append(stroke_path(d, whisker, 1.9))
    return out


def dog(coat: str, mood: str) -> list[str]:
    c = DOGS[coat]
    dark = c.get("dark", False)
    ink = LIGHT if dark else INK
    line = c["line"]
    ear_line = "#93613E" if coat == "spotted" else line
    out = []

    # Sarkık kulaklar (kafanın arkasında)
    out.append(f'<ellipse cx="19.5" cy="68" rx="12.5" ry="25" fill="{c["ear"]}" stroke="{ear_line}" stroke-width="3" transform="rotate(13 19.5 68)"/>')
    out.append(f'<ellipse cx="100.5" cy="68" rx="12.5" ry="25" fill="{c["ear"]}" stroke="{ear_line}" stroke-width="3" transform="rotate(-13 100.5 68)"/>')

    # Kafa
    out.append(ellipse(60, 64, 39, 37, c["fur"]))
    if c.get("patch"):
        out.append(ellipse(43.5, 60, 14, 15.5, c["patch"]))
    out.append(ellipse(60, 82, 20.5, 15, c["muzzle"]))
    out.append(f'<ellipse cx="60" cy="64" rx="39" ry="37" fill="none" stroke="{line}" stroke-width="3"/>')

    # Yüz
    out += blush(31, 89, 78, mood == "happy")
    if c.get("brows") and mood != "hungry":
        out.append(ellipse(44, 49.5, 3.6, 2.6, c["brows"]))
        out.append(ellipse(76, 49.5, 3.6, 2.6, c["brows"]))
    out += eyes(44, 76, 62, mood, dark, iris="#B98654" if dark else None)
    out.append(ellipse(60, 74.5, 7, 5.2, "#2E2422"))
    out.append(ellipse(58.2, 73, 2.2, 1.2, "#FFFFFF", ' opacity="0.55"'))
    muzzle_ink = INK  # ağız her zaman açık renk burun bölgesinin üstünde
    if mood == "happy":
        out.append(f'<path d="M50.5 83.5 Q60 99 69.5 83.5 Z" fill="{MOUTH_IN}"/>')
        out.append(ellipse(60, 91.6, 5, 4.4, TONGUE))
        out.append(stroke_path("M50.5 83.5 Q55.5 86.5 60 81 Q64.5 86.5 69.5 83.5", muzzle_ink, 2.4))
    elif mood == "hungry":
        out.append(stroke_path("M60 79.7 L60 83", muzzle_ink, 2.2))
        out.append(ellipse(60, 88, 4.6, 4.8, MOUTH_IN))
        out.append(ellipse(60, 90.2, 3, 2.2, TONGUE))
    else:
        out.append(stroke_path("M60 79.7 L60 83.5", muzzle_ink, 2.2))
        out.append(stroke_path("M51.5 84.5 Q55.8 89.5 60 83.5 Q64.2 89.5 68.5 84.5", muzzle_ink, 2.4))
    _ = ink
    return out


def group(parts: list[str], transform: str) -> list[str]:
    return [f'<g transform="{transform}">'] + parts + ["</g>"]


def duo(mood: str) -> list[str]:
    """Kedi ve köpek yan yana: 'kedi ve köpek' noktaları, karşılama ekranı."""
    return group(dog("cream", mood), "translate(40 16) scale(0.68)") + group(cat("orange", mood), "translate(-4 24) scale(0.68)")


def paw(cx, cy, scale, color):
    parts = [ellipse(cx, cy + 3 * scale, 5.2 * scale, 4.3 * scale, color)]
    for dx, dy in ((-6.4, -3.2), (-2.3, -7.4), (2.3, -7.4), (6.4, -3.2)):
        parts.append(ellipse(cx + dx * scale, cy + dy * scale, 2.2 * scale, 2.8 * scale, color))
    return parts


def bowl(body, rim, line, y=0.0):
    return [
        f'<path d="M24 {f(62 + y)} L96 {f(62 + y)} L88.5 {f(92 + y)} Q87 {f(99 + y)} 79 {f(99 + y)} L41 {f(99 + y)} Q33 {f(99 + y)} 31.5 {f(92 + y)} Z" fill="{body}" stroke="{line}" stroke-width="3" stroke-linejoin="round"/>',
        f'<rect x="19" y="{f(55 + y)}" width="82" height="12" rx="6" fill="{rim}" stroke="{line}" stroke-width="3"/>',
    ]


def spot_food() -> list[str]:
    out = [ellipse(60, 56, 31, 15, "#B9825A", ' stroke="#8F5E3C" stroke-width="3"')]
    for x, y in ((46, 50), (58, 46), (71, 50), (52, 57), (65, 57), (78, 57), (40, 58)):
        out.append(f'<circle cx="{x}" cy="{y}" r="4.6" fill="#D6A072"/>')
    out += bowl("#FF9DB0", "#FFC2CE", "#E0718A")
    out += paw(60, 83, 1.25, "#FFFFFF")
    return out


def spot_water() -> list[str]:
    out = [f'<path d="M60 14 C68 27 74 33.5 74 41.5 A14 14 0 0 1 46 41.5 C46 33.5 52 27 60 14 Z" fill="#7CC4F2" stroke="#4E9FD6" stroke-width="3" stroke-linejoin="round"/>',
           ellipse(55, 40, 3, 4.6, "#FFFFFF", ' opacity="0.7"')]
    out += bowl("#7CC4F2", "#B6E0FA", "#4E9FD6")
    out.append(stroke_path("M38 79 Q44 74.5 50 79 Q56 83.5 62 79 Q68 74.5 74 79 Q78 82 82 79", "#FFFFFF", 3))
    return out


def spot_shelter() -> list[str]:
    return [
        '<rect x="27" y="56" width="66" height="46" rx="7" fill="#F8D8A0" stroke="#D9AA5E" stroke-width="3"/>',
        '<path d="M14 60 L60 19 L106 60 Z" fill="#F0806F" stroke="#C95B4C" stroke-width="3" stroke-linejoin="round"/>',
        '<path d="M46 102 L46 82 A14 14 0 0 1 74 82 L74 102 Z" fill="#7A4B3A"/>',
        f'<path d="M60 49.5 C57.5 45.5 51.5 46.5 51.5 51 C51.5 54.8 56 57.6 60 61 C64 57.6 68.5 54.8 68.5 51 C68.5 46.5 62.5 45.5 60 49.5 Z" fill="#FFFFFF" transform="translate(0 -9)"/>',
        ellipse(55, 88, 2.3, 2.9, "#F7DC6A"),
        ellipse(65, 88, 2.3, 2.9, "#F7DC6A"),
    ]


def spot_mixed() -> list[str]:
    out = [ellipse(52, 58, 27, 13, "#B9825A", ' stroke="#8F5E3C" stroke-width="3"')]
    for x, y in ((40, 53), (51, 49), (62, 53), (46, 59), (58, 59)):
        out.append(f'<circle cx="{x}" cy="{y}" r="4.3" fill="#D6A072"/>')
    out += bowl("#FF9DB0", "#FFC2CE", "#E0718A")
    out += paw(52, 83, 1.15, "#FFFFFF")
    out.append('<path d="M89 22 C95.5 32 100 37 100 43.5 A11 11 0 0 1 78 43.5 C78 37 82.5 32 89 22 Z" fill="#7CC4F2" stroke="#4E9FD6" stroke-width="3" stroke-linejoin="round"/>')
    out.append(ellipse(85.5, 42, 2.4, 3.6, "#FFFFFF", ' opacity="0.7"'))
    return out


def app_icon(dark: bool) -> str:
    """1024×1024 uygulama ikonu: mint zeminde beyaz harita pini, içinde sarman kedi."""
    top, bottom = ("#1B2A23", "#0F1613") if dark else ("#DDF3E8", "#8ED8B5")
    pin = "#F4FAF7" if dark else "#FFFFFF"
    shadow = "0.35" if dark else "0.16"
    face = "\n    ".join(cat("orange", "neutral"))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <ellipse cx="512" cy="930" rx="150" ry="26" fill="#000000" opacity="{shadow}"/>
  <path d="M512 928 C436 800 196 664 196 440 A316 316 0 1 1 828 440 C828 664 588 800 512 928 Z" fill="{pin}"/>
  <g transform="translate(224 126) scale(4.8)">
    {face}
  </g>
</svg>
"""


def svg(parts: list[str]) -> str:
    body = "\n  ".join(parts)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">\n'
            f"  {body}\n</svg>\n")


def all_assets() -> dict[str, str]:
    assets: dict[str, str] = {}
    for coat in CATS:
        for mood in MOODS:
            assets[f"mascot-cat-{coat}-{mood}"] = svg(cat(coat, mood))
    for coat in DOGS:
        for mood in MOODS:
            assets[f"mascot-dog-{coat}-{mood}"] = svg(dog(coat, mood))
    for mood in MOODS:
        assets[f"mascot-duo-{mood}"] = svg(duo(mood))
    assets["spot-food"] = svg(spot_food())
    assets["spot-water"] = svg(spot_water())
    assets["spot-shelter"] = svg(spot_shelter())
    assets["spot-mixed"] = svg(spot_mixed())
    return assets


def write_catalog(assets: dict[str, str]) -> None:
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    CATALOG.mkdir(parents=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for name, content in sorted(assets.items()):
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir()
        (folder / f"{name}.svg").write_text(content, encoding="utf-8")
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        }, indent=2) + "\n")


def write_preview(assets: dict[str, str], directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    cells = []
    for name, content in sorted(assets.items()):
        inline = content.split("?>", 1)[1]
        small = inline.replace('width="120" height="120"', 'width="38" height="38"')
        cells.append(
            f'<div class="cell"><div class="big">{inline}</div>'
            f'<div class="pins"><span class="pin g">{small}</span><span class="pin o">{small}</span><span class="pin d">{small}</span></div>'
            f'<div class="name">{name}</div></div>'
        )
    html = f"""<!doctype html><meta charset="utf-8"><title>Maskotlar</title>
<body style="margin:0;background:#E9F5F0;font:12px -apple-system,Helvetica,Arial,sans-serif;color:#13201A">
<div style="display:grid;grid-template-columns:repeat(6,1fr);gap:14px;padding:18px">
{''.join(cells)}
</div>
<style>
.cell{{background:#fff;border-radius:18px;padding:12px 8px;text-align:center;box-shadow:0 4px 12px rgba(0,0,0,.06)}}
.big svg{{width:124px;height:124px}}
.pins{{display:flex;gap:10px;justify-content:center;margin:6px 0 8px}}
.pin{{width:42px;height:42px;border-radius:50%;display:flex;align-items:center;justify-content:center;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,.18)}}
.pin.g{{border:3px solid #3BB273}} .pin.o{{border:3px solid #F28C38}} .pin.d{{border:3px solid #A0A7A4;background:#1E2925}}
.name{{font-size:11px;color:#56645E}}
</style></body>"""
    (directory / "preview.html").write_text(html, encoding="utf-8")


def main() -> int:
    assets = all_assets()
    write_catalog(assets)
    print(f"{len(assets)} ikon → {CATALOG.relative_to(ROOT)}")
    if "--app-icon" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--app-icon") + 1])
        target.mkdir(parents=True, exist_ok=True)
        (target / "appicon.svg").write_text(app_icon(dark=False), encoding="utf-8")
        (target / "appicon-dark.svg").write_text(app_icon(dark=True), encoding="utf-8")
        print(f"uygulama ikonu SVG → {target} (PNG'ye çevirip Assets.xcassets/AppIcon.appiconset içine koyun)")
    if "--preview" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--preview") + 1])
        write_preview(assets, target)
        print(f"önizleme → {target / 'preview.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
