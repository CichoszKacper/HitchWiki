# The HitchWise mark: a hitchhiker's cardboard sign with a thumbs-up sticker in front of it.
# Writes the two layers as SVG (sign, thumb). They share one canvas so they line up when stacked;
# the launch screen and SplashView show them as the LaunchSign / LaunchThumb images (210 x 210 pt).
#
#   python3 mark.py                      -> launch-sign.svg, launch-thumb.svg
#   render each at 210, 420 and 630 px with a transparent background (any SVG renderer, e.g. a
#   headless browser) into HitchWiki/Assets.xcassets/LaunchSign|LaunchThumb.imageset
THUMB = "M86 106 C78 84 80 56 92 33 C99 20 119 20 122 35 C125 56 119 76 121 96 Z"
PARTS = [
    ('rect', dict(x=64, y=96, width=62, height=86, rx=16)),
    ('rect', dict(x=96, y=96, width=70, height=24, rx=12)),
    ('rect', dict(x=100, y=117, width=68, height=23, rx=11.5)),
    ('rect', dict(x=100, y=137, width=64, height=23, rx=11.5)),
    ('rect', dict(x=98, y=157, width=56, height=23, rx=11.5)),
]
def el(kind, attrs, extra=''):
    a = ' '.join(f'{k.replace("_","-")}="{v}"' for k, v in attrs.items())
    return f'<{kind} {a} {extra}/>'
def hand(fill, sleeve, outline='#fff', outline_w=16, creases='#C9531E', nail=True):
    parts = [('path', dict(d=THUMB))] + PARTS
    out = []
    if outline:
        out.append(f'<g stroke="{outline}" stroke-width="{outline_w}" stroke-linejoin="round" fill="{outline}">')
        out.append(el('rect', dict(x=34, y=96, width=34, height=86, rx=9)))
        out += [el(k, a) for k, a in parts]
        out.append('</g>')
    out.append(el('rect', dict(x=34, y=96, width=34, height=86, rx=9), f'fill="{sleeve}"'))
    out.append(f'<g fill="{fill}">' + ''.join(el(k, a) for k, a in parts) + '</g>')
    out.append(f'<g stroke="{creases}" stroke-opacity="0.5" stroke-width="3" stroke-linecap="round" fill="none">'
               '<path d="M118 118.5 H160"/><path d="M118 138.5 H158"/><path d="M116 158.5 H150"/></g>')
    if nail:
        out.append('<path d="M97 44 C99 34 112 32 115 42 L114 54 C109 51 102 51 97 54 Z" fill="#fff" fill-opacity="0.35"/>')
    return ''.join(out)

DEFS = '''<defs>
<linearGradient id="kraft" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4CF97"/><stop offset="1" stop-color="#DCA463"/></linearGradient>
<linearGradient id="skin" gradientUnits="userSpaceOnUse" x1="0" y1="25" x2="0" y2="185"><stop offset="0" stop-color="#FFC27C"/><stop offset="1" stop-color="#EE6A2C"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="9" stdDeviation="9" flood-color="#000" flood-opacity="0.32"/></filter>
<filter id="sh2" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="5" stdDeviation="5" flood-color="#000" flood-opacity="0.28"/></filter>
</defs>'''

def sign(x, y, w, h, angle, cx, cy, extra=''):
    return (f'<g transform="rotate({angle} {cx} {cy})" filter="url(#sh)">'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#kraft)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="none" stroke="#B57E45" stroke-opacity="0.55" stroke-width="3"/>'
            # cardboard corrugation hint
            f'<path d="M{x+14} {y+h-14} H{x+w-14}" stroke="#B57E45" stroke-opacity="0.25" stroke-width="2" stroke-dasharray="2 5"/>'
            f'{extra}</g>')

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240">{DEFS}{body}</svg>'

def layer(body):
    # 20-unit margin all round so the shadows aren't cut off
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-20 -20 280 280">{DEFS}{body}</svg>'

sign_layer = layer(sign(14, 84, 212, 116, -8, 120, 142,
                        '<rect x="30" y="72" width="40" height="18" rx="3" fill="#fff" fill-opacity="0.8" transform="rotate(-14 50 81)"/>'))
thumb_layer = layer(f'<g transform="translate(50 6) scale(1.02) rotate(8 100 110)" filter="url(#sh2)">{hand("url(#skin)", "#2E3192")}</g>')
open('launch-sign.svg', 'w').write(sign_layer)
open('launch-thumb.svg', 'w').write(thumb_layer)
