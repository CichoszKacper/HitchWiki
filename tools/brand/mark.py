# The HitchWise mark: a hitchhiker's cardboard sign with a thumbs-up sticker in front of it.
# Writes the two layers as SVG (sign, thumb). They share one canvas so they line up when stacked;
# the launch screen and SplashView show them as the LaunchSign / LaunchThumb images (210 x 210 pt).
#
#   python3 mark.py                      -> launch-sign.svg, launch-thumb.svg
#   render each at 210, 420 and 630 px with a transparent background (any SVG renderer, e.g. a
#   headless browser) into HitchWiki/Assets.xcassets/LaunchSign|LaunchThumb.imageset

def el(kind, attrs, extra=''):
    a = ' '.join(f'{k.replace("_","-")}="{v}"' for k, v in attrs.items())
    return f'<{kind} {a} {extra}/>'

# --- The hand (200-unit canvas): sleeve on the left, fingers curled to the right, and a thumb shaped like the
#     fingers (same width, same rounded ends) standing up, with a small nail.
SLEEVE = dict(x=34, y=104, width=30, height=78, rx=8)
FIST = [
    ('rect', dict(x=60, y=100, width=62, height=82, rx=16)),
    ('rect', dict(x=92, y=100, width=66, height=22, rx=11)),
    ('rect', dict(x=96, y=120, width=66, height=21, rx=10.5)),
    ('rect', dict(x=96, y=139, width=62, height=21, rx=10.5)),
    ('rect', dict(x=94, y=158, width=54, height=22, rx=11)),
]
THUMB = dict(x=70, y=58, width=22, height=56, rx=11, transform='rotate(-6 81 110)')
NAIL = dict(x=74, y=61, width=14, height=11, rx=5, transform='rotate(-6 81 110)')

def hand():
    parts = [('rect', THUMB)] + FIST
    return ''.join([
        # white die-cut sticker edge: every part stroked thick, fills drawn over it
        '<g stroke="#fff" stroke-width="14" stroke-linejoin="round" fill="#fff">',
        el('rect', SLEEVE), *[el(k, a) for k, a in parts], '</g>',
        el('rect', SLEEVE, 'fill="#2E3192"'),
        '<g fill="url(#skin)">' + ''.join(el(k, a) for k, a in parts) + '</g>',
        '<g stroke="#C9531E" stroke-opacity="0.5" stroke-width="3" stroke-linecap="round" fill="none">'
        '<path d="M114 121 H156"/><path d="M114 140 H154"/><path d="M112 159 H146"/>'
        '<path d="M70 104 C76 101 84 100 92 101"/></g>',
        el('rect', NAIL, 'fill="#FFE2C4" fill-opacity="0.9" stroke="#E07A3F" stroke-opacity="0.5" stroke-width="1.5"'),
    ])

DEFS = '''<defs>
<linearGradient id="kraft" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4CF97"/><stop offset="1" stop-color="#DCA463"/></linearGradient>
<linearGradient id="skin" gradientUnits="userSpaceOnUse" x1="0" y1="50" x2="0" y2="185"><stop offset="0" stop-color="#FFC27C"/><stop offset="1" stop-color="#EE6A2C"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="9" stdDeviation="9" flood-color="#000" flood-opacity="0.32"/></filter>
<filter id="sh2" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="5" stdDeviation="5" flood-color="#000" flood-opacity="0.28"/></filter>
</defs>'''

def sign():
    x, y, w, h = 14, 70, 212, 128
    return (f'<g transform="rotate(-8 120 134)" filter="url(#sh)">'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#kraft)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="none" stroke="#B57E45" stroke-opacity="0.55" stroke-width="3"/>'
            f'<path d="M{x+14} {y+h-14} H{x+w-14}" stroke="#B57E45" stroke-opacity="0.25" stroke-width="2" stroke-dasharray="2 5"/>'
            '<rect x="30" y="58" width="40" height="18" rx="3" fill="#fff" fill-opacity="0.8" transform="rotate(-14 50 67)"/>'
            '</g>')

def layer(body):
    # 20-unit margin all round so the shadows aren't cut off
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-20 -20 280 280">{DEFS}{body}</svg>'

open('launch-sign.svg', 'w').write(layer(sign()))
# The thumb sits on the right half of the sign and only just peeks over its top edge.
open('launch-thumb.svg', 'w').write(layer(
    f'<g transform="translate(66 26) scale(0.86) rotate(6 100 120)" filter="url(#sh2)">{hand()}</g>'))
