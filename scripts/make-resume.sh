#!/usr/bin/env bash
# Renders assets/resume/resume.html (the public web edition) to static/resume.pdf with headless Chrome.
# Run after editing the resume source; then run `bash tests/verify-site.sh resume`.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
OUT="$ROOT/static/resume.pdf"
"$CHROME" --headless=new --no-pdf-header-footer --allow-file-access-from-files \
  --print-to-pdf="$OUT" "file://$ROOT/assets/resume/resume.html" 2>/dev/null
echo "wrote $OUT"
