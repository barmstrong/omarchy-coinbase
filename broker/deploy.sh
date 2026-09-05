#!/usr/bin/env bash
# Deploy the Coinbase OAuth broker to Cloudflare Workers and write broker.url
# for the plugin. Run from anywhere; uses this directory.
set -euo pipefail

cd "$(dirname "$0")"
wrangler=(npx --yes wrangler@4.129.0)

if ! "${wrangler[@]}" whoami >/dev/null 2>&1; then
  echo "Log in to Cloudflare first (opens a browser):"
  echo "  npx --yes wrangler@4.129.0 login"
  echo "Then run this script again."
  exit 1
fi

echo "Deploying omarchy-oauth worker…"
deploy_out=$("${wrangler[@]}" deploy 2>&1 | tee /dev/stderr)
url=$(grep -Eo 'https://[a-zA-Z0-9._-]+\.workers\.dev' <<<"$deploy_out" | head -n1)
if [[ -z ${url:-} ]]; then
  echo "Deploy finished but no workers.dev URL was printed. Set broker.url by hand." >&2
  exit 1
fi

printf '%s\n' "$url" > ../broker.url
echo
echo "Broker URL: $url"
echo "Wrote $(realpath ../broker.url)"
echo
echo "Now store the Coinbase OAuth app credentials (paste when prompted):"
"${wrangler[@]}" secret put COINBASE_CLIENT_ID
"${wrangler[@]}" secret put COINBASE_CLIENT_SECRET
echo
echo "In the Coinbase OAuth app, set the redirect URI to exactly:"
echo "  ${url}/oauth/callback"
echo
echo "Then rsync the plugin (so broker.url is on the bar) and click Sign in."
