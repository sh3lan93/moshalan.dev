#!/usr/bin/env bash
# Renders assets/og/card.html to static/images/og-default.png (1200x630) with headless Chrome.
# Run after changing the positioning line or avatar.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
OUT="$ROOT/static/images/og-default.png"
mkdir -p "$(dirname "$OUT")"
# Headless Chrome enforces a minimum window width; 1200 is above it, so the capture is exact.
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 \
  --allow-file-access-from-files --virtual-time-budget=3000 \
  --window-size=1200,630 --screenshot="$OUT" "file://$ROOT/assets/og/card.html" 2>/dev/null
echo "wrote $OUT"
