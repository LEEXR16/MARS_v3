"""Draws the app icon (the MARS lever on Mars, in its 60-120 deg window) and renders one PNG with
headless Edge. The launcher icons in android/app/src/main/res/mipmap-*/ were made with it:
  ic_launcher.png             full   48 / 72 / 96 / 144 / 192   (mdpi .. xxxhdpi)
  ic_launcher_foreground.png  fg    108 / 162 / 216 / 324 / 432  (Android 8+ adaptive icon)
usage: python make_icon.py <outdir> full|fg <size> <name>"""
import os
import subprocess
import sys

out, mode, size, name = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

BG = '''<defs>
 <radialGradient id="bgG" cx="50%" cy="38%" r="75%"><stop offset="0" stop-color="#2A1D11"/><stop offset="1" stop-color="#0A0705"/></radialGradient>
</defs><rect width="1024" height="1024" fill="url(#bgG)"/>'''

# planet centred at (512, 600) r 300; lever from the pivot up to y 160; window arc r 400, 60-120 deg
ART = '''<defs>
 <radialGradient id="mars" cx="38%" cy="32%" r="78%"><stop offset="0" stop-color="#FFC27A"/><stop offset=".55" stop-color="#E0873E"/><stop offset="1" stop-color="#7A3E1A"/></radialGradient>
 <clipPath id="disc"><circle cx="512" cy="600" r="300"/></clipPath>
</defs>
<circle cx="512" cy="600" r="300" fill="url(#mars)"/>
<g clip-path="url(#disc)" fill="none" stroke="#5A2C12" stroke-opacity=".35" stroke-width="22" stroke-linecap="round">
 <path d="M200 520 Q 512 470 824 540"/><path d="M220 700 Q 512 650 800 720"/>
 <circle cx="650" cy="470" r="38" fill="#5A2C12" fill-opacity=".25" stroke="none"/>
 <circle cx="390" cy="790" r="26" fill="#5A2C12" fill-opacity=".25" stroke="none"/>
</g>
<g fill="none" stroke="#FFDC8F" stroke-linecap="round">
 <path d="M 297 234.9 A 420 420 0 0 1 727 234.9" stroke-width="22"/>
 <line x1="282" y1="209" x2="312" y2="261" stroke-width="22"/><line x1="742" y1="209" x2="712" y2="261" stroke-width="22"/>
</g>
<line x1="512" y1="600" x2="606" y2="249" stroke="#F5E9D8" stroke-width="60" stroke-linecap="round"/>
<circle cx="606" cy="249" r="40" fill="#FFDC8F"/>
<circle cx="512" cy="600" r="62" fill="#F5E9D8"/><circle cx="512" cy="600" r="26" fill="#16100B"/>'''


def placed(scale):
    # the art spans y 156..900 (centre ~528); centre it on the canvas
    return f'<g transform="translate(512 512) scale({scale}) translate(-512 -528)">{ART}</g>'


body = {'full': BG + placed(0.86), 'fg': placed(0.58)}[mode]
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="{size}" height="{size}">{body}</svg>'
html = os.path.join(out, f'{name}.html')
with open(html, 'w') as f:
    f.write(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
with open(os.path.join(out, f'{name}.svg'), 'w') as f:
    f.write(svg)

edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
png = os.path.join(out, f'{name}.png')
subprocess.run([edge, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000',
                f'--window-size={size},{size}', f'--screenshot={png}', '--user-data-dir=' + os.path.join(out, 'prof'),
                'file:///' + html.replace(os.sep, '/')],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
print(png, os.path.getsize(png))
