#!/bin/bash
# scripts/gen-icons.sh: Render favicons and the share preview image.
# Sources: static/favicon.svg (mark) and scripts/og.svg (1200x630 preview).
# Requires rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# PNG and ICO cannot follow the color scheme: use the dark-mode ring color.
sed 's|<style>.*</style>|<style>circle{stroke:#3B82F6}</style>|' static/favicon.svg > "$tmp/mark.svg"
for n in 16 32 48 180 192 512; do
    rsvg-convert -w "$n" -h "$n" "$tmp/mark.svg" -o "$tmp/$n.png"
done
cp "$tmp/16.png" static/favicon-16x16.png
cp "$tmp/32.png" static/favicon-32x32.png
cp "$tmp/180.png" static/apple-touch-icon.png
cp "$tmp/192.png" static/android-chrome-192x192.png
cp "$tmp/512.png" static/android-chrome-512x512.png

# ICO with embedded PNG entries (16, 32, 48).
python3 - "$tmp" static/favicon.ico <<'PY'
import struct, sys
src, out = sys.argv[1], sys.argv[2]
sizes = (16, 32, 48)
imgs = [open(f"{src}/{n}.png", "rb").read() for n in sizes]
off = 6 + 16 * len(imgs)
entries = b""
for n, data in zip(sizes, imgs):
    entries += struct.pack("<BBBBHHII", n, n, 0, 0, 1, 32, len(data), off)
    off += len(data)
with open(out, "wb") as f:
    f.write(struct.pack("<HHH", 0, 1, len(imgs)) + entries + b"".join(imgs))
PY

rsvg-convert -w 1200 -h 630 scripts/og.svg -o static/og.png
