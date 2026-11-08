"""Draws SDM's logo and launcher icons (vector design rendered with Chromium).

  assets/icon/logo.png     logo for About (rounded square)
  assets/icon/icon.png     launcher icon, full square (older Androids)
  assets/icon/icon_fg.png  adaptive icon foreground (the glyph, transparent)
  assets/icon/icon_bg.png  adaptive icon background (the gradient)

Run:  python3 tool/make_icon.py"""
from playwright.sync_api import sync_playwright

DEFS = """
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#101827"/><stop offset="1" stop-color="#05080F"/>
  </linearGradient>
  <linearGradient id="g1" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFB84D"/><stop offset="1" stop-color="#FF4D6D"/>
  </linearGradient>
</defs>"""

# glyph drawn in a 1024 box, then moved so its content is centred on (512,512)
GLYPH = """
<g transform="translate(5 -32)">
  <path d="M512 760 L250 470 H400 L512 600 L624 470 H774 Z" fill="url(#g1)"/>
  <path d="M300 330 L420 330 L360 400 L240 400 Z" fill="url(#g1)" opacity=".55"/>
  <path d="M452 250 L572 250 L512 320 L392 320 Z" fill="url(#g1)" opacity=".8"/>
  <path d="M604 330 L724 330 L664 400 L544 400 Z" fill="url(#g1)" opacity=".55"/>
  <rect x="290" y="812" width="444" height="26" rx="13" fill="#FFB84D"/>
</g>"""


def svg(body, size=1024):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 1024 1024">{DEFS}{body}</svg>')


BG = '<rect width="1024" height="1024" fill="url(#bg)"/>'
ROUND = '<clipPath id="r"><rect width="1024" height="1024" rx="232"/></clipPath>'
full = svg(f'{ROUND}<g clip-path="url(#r)">{BG}</g>{GLYPH}')            # About logo
square = svg(f'{BG}<g transform="translate(512 512) scale(1.0) translate(-512 -512)">{GLYPH}</g>')
fg = svg(f'<g transform="translate(512 512) scale(.72) translate(-512 -512)">{GLYPH}</g>')
bg = svg(BG)

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1024, "height": 1024})
    for name, doc in [("logo", full), ("icon", square), ("icon_fg", fg), ("icon_bg", bg)]:
        pg.set_content(f'<body style="margin:0;background:transparent">{doc}</body>')
        pg.screenshot(path=f"assets/icon/{name}.png", omit_background=True)
    b.close()

# About shows the logo at ~130 px: 512 px is plenty and keeps the app small
from PIL import Image  # noqa: E402

Image.open("assets/icon/logo.png").resize((512, 512), Image.LANCZOS).save(
    "assets/icon/logo.png", optimize=True)
print("icons written")
