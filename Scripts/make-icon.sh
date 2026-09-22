#!/usr/bin/env bash
# Regenerates the app icon from the single source of truth, Resources/AppIcon.icon.
#
# macOS 26 and macOS 15 want different things from an app icon, so this emits both from
# the one document:
#
#   Assets.car   compiled by actool from AppIcon.icon. Tahoe reads it via CFBundleIconName
#                and renders the layers as Liquid Glass, generating the dark, clear and
#                tinted appearances itself.
#   AppIcon.icns the flat rendering for macOS 15 and earlier, read via CFBundleIconFile.
#                actool emits an .icns too, but only at four sizes (16, 32, 128, 256),
#                so we compose our own at all ten and overwrite it.
#
# The .icns is *derived* from the same layers rather than drawn separately: the layer art
# is authored full-bleed on the 1024 canvas Icon Composer uses, where the rounded rectangle
# is the canvas, and this script insets it onto the macOS grid (an 824 squircle in a 1024
# canvas, 824/1024 = 0.80469) and bakes in the shape, gradient and shadow that Tahoe would
# otherwise draw for us. Both stay in step with one edit.
#
# Only needed when the icon changes; build-app.sh just copies the committed output.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC="Resources/AppIcon.icon"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun --find actool >/dev/null 2>&1 || {
	echo "error: actool not found. Full Xcode is required; Command Line Tools alone do not ship it." >&2
	exit 1
}

# --- 1. compose the flat 1024 artwork out of the same layers ----------------
python3 - "$SRC" "$WORK/legacy.svg" <<'PY'
import json, re, sys, pathlib

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
doc = json.loads((src / "icon.json").read_text())

def hexof(spec):
    # Colours are "<colourspace>:r,g,b,a" with components in 0...1.
    r, g, b = (float(c) for c in spec.split(":", 1)[1].split(",")[:3])
    return "#%02X%02X%02X" % tuple(min(255, max(0, round(v * 255))) for v in (r, g, b))

fill = doc.get("fill", {})
if "linear-gradient" in fill:
    stops = [hexof(c) for c in fill["linear-gradient"]]
elif "solid" in fill:
    stops = [hexof(fill["solid"])] * 2
elif "automatic-gradient" in fill:
    stops = [hexof(fill["automatic-gradient"])] * 2
else:
    raise SystemExit("icon.json: unsupported fill %r" % list(fill))
top, bottom = stops[0], stops[-1]

# Inline each layer, bottom group first, which is the order icon.json lists them in.
# Ids are namespaced per layer so two layers may both define e.g. a "fade" gradient.
body, n = [], 0
for group in doc.get("groups", []):
    if group.get("hidden"):
        continue
    for layer in group.get("layers", []):
        if layer.get("hidden"):
            continue
        n += 1
        art = (src / "Assets" / layer["image-name"]).read_text()
        inner = re.sub(r"(?s)^.*?<svg[^>]*>|</svg>\s*$", "", art)
        for i in set(re.findall(r'id="([^"]+)"', inner)):
            inner = inner.replace('id="%s"' % i, 'id="L%d_%s"' % (n, i))
            inner = inner.replace('url(#%s)' % i, 'url(#L%d_%s)' % (n, i))
        body.append(inner)

out.write_text('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0.25" y2="1">
    <stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>
  </linearGradient>
  <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.20"/>
    <stop offset="0.55" stop-color="#ffffff" stop-opacity="0"/>
  </linearGradient>
  <filter id="sh" x="-25%%" y="-25%%" width="150%%" height="150%%">
    <feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#000000" flood-opacity="0.30"/>
  </filter>
</defs>
<g filter="url(#sh)">
  <rect x="100" y="94" width="824" height="824" rx="186" fill="url(#bg)"/>
  <rect x="100" y="94" width="824" height="824" rx="186" fill="url(#gloss)"/>
</g>
<g transform="translate(100,94) scale(0.80469)">
%s
</g>
</svg>
''' % (top, bottom, "".join(body)))
PY

# --- 2. rasterise it at every size the iconset needs ------------------------
# Built into .build so the binary stays out of the repo.
RENDER=".build/rendersvg"
mkdir -p .build
if [[ ! -x "$RENDER" || Scripts/rendersvg.swift -nt "$RENDER" ]]; then
	swiftc -O Scripts/rendersvg.swift -o "$RENDER"
fi

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 64 128 256 512 1024; do
	"./$RENDER" "$WORK/legacy.svg" "$WORK/$size.png" "$size"
done
cp "$WORK/16.png"   "$SET/icon_16x16.png"
cp "$WORK/32.png"   "$SET/icon_16x16@2x.png"
cp "$WORK/32.png"   "$SET/icon_32x32.png"
cp "$WORK/64.png"   "$SET/icon_32x32@2x.png"
cp "$WORK/128.png"  "$SET/icon_128x128.png"
cp "$WORK/256.png"  "$SET/icon_128x128@2x.png"
cp "$WORK/256.png"  "$SET/icon_256x256.png"
cp "$WORK/512.png"  "$SET/icon_256x256@2x.png"
cp "$WORK/512.png"  "$SET/icon_512x512.png"
cp "$WORK/1024.png" "$SET/icon_512x512@2x.png"

# --- 3. compile both products ----------------------------------------------
mkdir -p "$WORK/car"
xcrun actool --compile "$WORK/car" --app-icon AppIcon --platform macosx \
	--minimum-deployment-target 15.0 \
	--output-partial-info-plist "$WORK/icon-info.plist" \
	--errors --warnings "$SRC" >/dev/null

cp "$WORK/car/Assets.car" Resources/Assets.car
# Ours, not actool's four-size one.
iconutil --convert icns "$SET" --output Resources/AppIcon.icns

echo "Resources/AppIcon.icns  $(du -h Resources/AppIcon.icns | cut -f1)"
echo "Resources/Assets.car    $(du -h Resources/Assets.car | cut -f1)"
