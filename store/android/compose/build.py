#!/usr/bin/env python3
"""Google Play graphics for the BizHub POS app.

  1. tool/store_shots.sh
     → test/store/out/<lang>-<kind>-<n>-<name>.png       (real POS screens with the demo shops, phone 1080×2340)
       test/store/out/<lang>-<kind>-tab-<n>-<name>.png   (tablet 2560×1600, uploaded as they are)
  2. python3 store/android/compose/build.py
     → store/android/screenshots/<lang>/NN-name.png   (1080×1920, phone frame + headline)
       store/android/screenshots/<lang>-tablet/NN-name.png  (2560×1600, the tablet screens)
       store/android/feature-graphic-<lang>.png        (1024×500)
       store/android/icon-512.png                      (512×512)

Needs: Python 3 + Pillow + Playwright (Chromium). Fonts come from the app's assets/fonts.
"""
import json
import pathlib
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parents[2]  # bizhub-app-pos/
SHOTS = APP / "test/store/out"
OUT = HERE.parent  # store/android/
TMP = HERE / ".tmp"
TMP.mkdir(exist_ok=True)
FONTS = APP / "assets/fonts"

BG = {
    "sunrise": ("linear-gradient(160deg,#C8430F 0%,#E0581A 38%,#F28A26 74%,#FFB54C 100%)", "#fff"),
    "cream": ("linear-gradient(170deg,#FFF6EE 0%,#FFE7D3 60%,#FFD7B8 100%)", "#1B1410"),
    "night": ("radial-gradient(120% 80% at 80% 100%,rgba(224,88,26,.55) 0%,rgba(224,88,26,0) 60%),linear-gradient(170deg,#101016 0%,#1A1416 60%,#24160F 100%)", "#fff"),
    "plum": ("radial-gradient(100% 70% at 15% 105%,rgba(255,138,61,.6) 0%,rgba(255,138,61,0) 60%),linear-gradient(160deg,#24102F 0%,#4B1A4F 55%,#8A2D4A 100%)", "#fff"),
    "amber": ("linear-gradient(165deg,#FFC24D 0%,#FF9F2E 50%,#F2711C 100%)", "#26140A"),
    "teal": ("radial-gradient(110% 70% at 90% 105%,rgba(224,88,26,.55) 0%,rgba(224,88,26,0) 60%),linear-gradient(165deg,#0B3B3A 0%,#0F5D58 55%,#10726A 100%)", "#fff"),
}


def font_css():
    faces = []
    for w in (400, 500, 600, 700, 800):
        faces.append(f"@font-face{{font-family:'Jakarta';font-weight:{w};src:url('file://{FONTS}/PlusJakartaSans-{w}.ttf')}}")
    for w in (400, 500, 600, 700):
        faces.append(f"@font-face{{font-family:'Kantumruy';font-weight:{w};src:url('file://{FONTS}/KantumruyPro-{w}.ttf')}}")
    return "\n".join(faces)


def bbox(img, bg, tol=12, region=None):
    """bounding box of the pixels that differ from the background colour"""
    im = img.convert("RGB")
    if region:
        im = im.crop(region)
    w, h = im.size
    px = im.load()
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if abs(r - bg[0]) > tol or abs(g - bg[1]) > tol or abs(b - bg[2]) > tol:
                xs.append(x)
                ys.append(y)
    ox, oy = (region[0], region[1]) if region else (0, 0)
    return (min(xs) + ox, min(ys) + oy, max(xs) + ox + 2, max(ys) + oy + 2)


# the app mark + the name (the wordmark file draws "Biz" and "Hub" apart, which reads oddly this small)
_MARK = '<svg viewBox="0 0 500 500" width="500" height="500"><path d="M40 40H250A210 210 0 0 1 460 250V460H250A210 210 0 0 1 40 250Z" fill="none" stroke="currentColor" stroke-width="40" stroke-linejoin="round"/><circle cx="250" cy="250" r="138" fill="none" stroke="currentColor" stroke-width="38"/><circle cx="250" cy="250" r="66" fill="none" stroke="currentColor" stroke-width="38"/></svg>'
LOGO = f"<span class='brand'>{_MARK}<b>BizHub POS</b></span>"
LOGO_DARK = LOGO


def top_colour(path):
    """the app's colour behind the status bar (the first rows of the screen)"""
    im = Image.open(path).convert("RGB")
    r, g, b = im.getpixel((6, 6))
    dark = (0.299 * r + 0.587 * g + 0.114 * b) < 140
    return f"rgb({r},{g},{b})", ("#fff" if dark else "#111")


STATUS_ICONS = """<svg width='92' height='22' viewBox='0 0 92 22' fill='currentColor'>
<rect x='0' y='13' width='5' height='8' rx='1.5'/><rect x='8' y='9' width='5' height='12' rx='1.5'/><rect x='16' y='5' width='5' height='16' rx='1.5'/><rect x='24' y='1' width='5' height='20' rx='1.5'/>
<path d='M47 6.5c4.6 0 8.6 1.7 11.5 4.5l-2.3 2.3c-2.4-2.2-5.6-3.5-9.2-3.5s-6.8 1.3-9.2 3.5l-2.3-2.3c2.9-2.8 6.9-4.5 11.5-4.5zm0 6c2.6 0 4.9 1 6.6 2.6L47 21.6l-6.6-6.5c1.7-1.6 4-2.6 6.6-2.6z'/>
<rect x='64' y='3' width='24' height='16' rx='4.5' fill='none' stroke='currentColor' stroke-width='2'/><rect x='67' y='6' width='16' height='10' rx='2'/><rect x='89.5' y='8' width='2.5' height='6' rx='1'/></svg>"""


def slide_html(lang, s, i):
    bg, ink = BG[s["bg"]]
    km = lang == "km"
    fam = "'Kantumruy','Jakarta'" if km else "'Jakarta','Kantumruy'"
    shot = f"file://{SHOTS}/{lang}-{s['shot']}.png"
    sb_bg, sb_ink = top_colour(SHOTS / f"{lang}-{s['shot']}.png")
    tilt = s.get("tilt", 0)
    extra = ""
    logo = LOGO if ink == "#fff" else LOGO_DARK
    shift = "-90px" if s.get("extra") else "0px"
    return f"""<!doctype html><html><head><meta charset='utf-8'><style>
{font_css()}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:1080px;height:1920px;overflow:hidden}}
body{{background:{bg};color:{ink};font-family:{fam};position:relative}}
.glow{{position:absolute;inset:0;background:radial-gradient(60% 40% at 50% 8%,rgba(255,255,255,.22),rgba(255,255,255,0) 70%)}}
.dots{{position:absolute;inset:0;opacity:.10;background-image:radial-gradient(currentColor 1.6px,transparent 1.8px);background-size:34px 34px;-webkit-mask-image:linear-gradient(180deg,#000 0%,transparent 45%)}}
.top{{position:absolute;top:96px;left:70px;right:70px;text-align:center}}
.logo{{height:44px;opacity:.92;margin-bottom:34px}}
.brand{{display:inline-flex;align-items:center;gap:14px;font-family:'Jakarta';font-weight:800;font-size:40px;letter-spacing:-.5px}}
.brand svg{{height:44px;width:44px}}
h1{{text-wrap:balance;font-weight:800;font-size:{70 if km else 78}px;line-height:{1.32 if km else 1.08};letter-spacing:{0 if km else -1.6}px;{'font-weight:700;' if km else ''}}}
p{{text-wrap:balance;margin-top:22px;font-size:{33 if km else 35}px;line-height:{1.55 if km else 1.35};font-weight:{500 if km else 500};opacity:.86}}
.phone{{position:absolute;left:50%;top:{560 if km else 540}px;width:760px;margin-left:calc(-380px + {shift});transform:rotate({tilt}deg);transform-origin:50% 0;
  border-radius:96px;padding:16px;background:linear-gradient(145deg,#2B2B31,#0B0B0E 55%,#1E1E23);
  box-shadow:0 60px 120px rgba(0,0,0,.38),0 18px 40px rgba(0,0,0,.25),inset 0 0 0 2px rgba(255,255,255,.08)}}
.screen{{border-radius:80px;overflow:hidden;position:relative;background:#000}}
.screen img{{display:block;width:728px}}
.status{{height:64px;display:flex;align-items:center;justify-content:space-between;padding:6px 58px 0 64px;font-family:'Jakarta';font-size:27px;letter-spacing:.3px}}
.status svg{{height:22px;width:auto}}
.cam{{position:absolute;top:18px;left:50%;width:30px;height:30px;margin-left:-15px;border-radius:50%;background:#0A0A0C;box-shadow:inset 0 0 0 4px #1A1A20}}
.float{{position:absolute;filter:drop-shadow(0 40px 60px rgba(0,0,0,.42))}}
.ticket{{width:470px;right:30px;top:{1160 if km else 1140}px;transform:rotate(7deg);border-radius:26px}}
.qrcard{{right:40px;top:{1170 if km else 1150}px;transform:rotate(6deg);background:#fff;border-radius:46px;padding:26px;width:430px}}
.qrcard img{{display:block;width:100%;border-radius:24px}}
</style></head><body>
<div class='glow'></div><div class='dots'></div>
<div class='top'><div class='logo'>{logo}</div><h1>{s['h']}</h1><p>{s['s']}</p></div>
<div class='phone'><div class='screen'><div class='status' style='background:{sb_bg};color:{sb_ink}'><b>9:41</b>{STATUS_ICONS}</div><img src='{shot}'><div class='cam'></div></div></div>
{extra}
</body></html>"""


FEATURE = {
    "en": ("The counter app for your staff", "Restaurant · Mini mart · Guest house · Works offline"),
    "km": ("កម្មវិធីលក់<br>សម្រាប់បុគ្គលិក", "ភោជនីយដ្ឋាន · ហាងទំនិញ · ផ្ទះសំណាក់ · ប្រើបានពេលគ្មានអ៊ីនធឺណិត"),
}


def feature_html(lang):
    km = lang == "km"
    fam = "'Kantumruy','Jakarta'" if km else "'Jakarta','Kantumruy'"
    h, s = FEATURE[lang]
    a = f"file://{SHOTS}/{lang}-restaurant-7-tables-busy.png"
    b = f"file://{SHOTS}/{lang}-mart-5-paid.png"
    return f"""<!doctype html><html><head><meta charset='utf-8'><style>
{font_css()}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:1024px;height:500px;overflow:hidden}}
body{{background:radial-gradient(70% 120% at 100% 100%,rgba(255,190,90,.55),rgba(255,190,90,0) 60%),linear-gradient(135deg,#B83A0C 0%,#E0581A 45%,#F28A26 100%);color:#fff;font-family:{fam};position:relative}}
.dots{{position:absolute;inset:0;opacity:.12;background-image:radial-gradient(#fff 1.4px,transparent 1.6px);background-size:26px 26px;-webkit-mask-image:linear-gradient(90deg,#000,transparent 60%)}}
.l{{position:absolute;left:58px;top:0;bottom:0;width:{560 if km else 540}px;display:flex;flex-direction:column;justify-content:center}}
.brand{{display:inline-flex;align-items:center;gap:12px;font-family:'Jakarta';font-weight:800;font-size:34px}}
.brand svg{{height:38px;width:38px}}
h1{{margin-top:26px;font-weight:{700 if km else 800};font-size:{44 if km else 50}px;line-height:{1.32 if km else 1.06};letter-spacing:{0 if km else -1}px}}
p{{margin-top:16px;font-size:{19 if km else 20}px;line-height:1.5;opacity:.9;font-weight:500}}
.ph{{position:absolute;width:250px;border-radius:38px;padding:8px;background:#111;box-shadow:0 30px 60px rgba(0,0,0,.35)}}
.ph img{{display:block;width:234px;border-radius:31px}}
.p1{{right:210px;top:70px;transform:rotate(-6deg)}}
.p2{{right:-20px;top:40px;transform:rotate(7deg)}}
</style></head><body><div class='dots'></div>
<div class='l'><div class='logo'>{LOGO}</div><h1>{h}</h1><p>{s}</p></div>
<div class='ph p1'><img src='{a}'></div><div class='ph p2'><img src='{b}'></div>
</body></html>"""


def main():
    slides = json.loads((HERE / "slides.json").read_text())
    langs = sys.argv[1:] or ["en", "km"]
    with sync_playwright() as pw:
        br = pw.chromium.launch()
        pg = br.new_page(viewport={"width": 1080, "height": 1920}, device_scale_factor=1)
        for lang in langs:
            d = OUT / "screenshots" / lang
            d.mkdir(parents=True, exist_ok=True)
            for i, s in enumerate(slides[lang]):
                f = TMP / f"{lang}-{s['id']}.html"
                f.write_text(slide_html(lang, s, i))
                pg.goto(f"file://{f}")
                pg.wait_for_load_state("networkidle")
                pg.evaluate("document.fonts.ready")
                pg.screenshot(path=str(d / f"{s['id']}.png"))
                print("wrote", d / f"{s['id']}.png")
        fp = br.new_page(viewport={"width": 1024, "height": 500}, device_scale_factor=1)
        for lang in langs:
            f = TMP / f"feature-{lang}.html"
            f.write_text(feature_html(lang))
            fp.goto(f"file://{f}")
            fp.evaluate("document.fonts.ready")
            fp.screenshot(path=str(OUT / f"feature-graphic-{lang}.png"))
            print("wrote", OUT / f"feature-graphic-{lang}.png")
        br.close()
    # tablet screenshots: the screens as they are (16:10), in the order of slides.json "tablet"
    for lang in langs:
        d = OUT / "screenshots" / f"{lang}-tablet"
        d.mkdir(parents=True, exist_ok=True)
        for i, shot in enumerate(slides["tablet"], 1):
            Image.open(SHOTS / f"{lang}-{shot}.png").convert("RGB").save(d / f"{i:02d}-{shot.replace('-tab-', '-')}.png")
            print("wrote", d / f"{i:02d}-{shot.replace('-tab-', '-')}.png")
    # the 512×512 store icon from the app icon (full square, Play rounds the corners itself)
    Image.open(APP / "assets/brand/pos-icon.png").convert("RGB").resize((512, 512), Image.LANCZOS).save(OUT / "icon-512.png")
    print("wrote", OUT / "icon-512.png")


if __name__ == "__main__":
    main()
