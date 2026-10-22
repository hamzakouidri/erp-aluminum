#!/usr/bin/env bash
# Publishes the website on https://warshate.web.app:
#   /      the landing page (website/)
#   /app/  the Flutter application, built for that path
#
# Run from the project root with Git Bash:  bash tool/deploy_website.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/website_deploy"
SITE="warshate"
PROJECT="erp-aluminum-701f9"

cd "$ROOT"
# Git Bash would rewrite "/app/" into a Windows path without MSYS_NO_PATHCONV.
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/ --no-wasm-dry-run

rm -rf "$OUT"
mkdir -p "$OUT/public"
cp -r website/. "$OUT/public/"
cp -r build/web "$OUT/public/app"

cat > "$OUT/firebase.json" <<EOF
{
  "hosting": {
    "site": "$SITE",
    "public": "public",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "/app/**", "destination": "/app/index.html" }
    ],
    "headers": [
      {
        "source": "/index.html",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
      }
    ]
  }
}
EOF

cd "$OUT"
firebase deploy --only hosting --project "$PROJECT" --non-interactive < /dev/null
echo "Published: https://$SITE.web.app  (application: https://$SITE.web.app/app/)"
