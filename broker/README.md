# Coinbase OAuth broker

Cloudflare Worker that holds your one Coinbase OAuth client secret so every
Omarchy installer can click Sign in.

Each active sign-in uses one SQLite-backed Durable Object. It contains only the
short-lived PKCE/session state. After the callback, the returned token bundle is
held only in the live object's memory while the desktop's pending poll claims
it; bearer credentials are never written to Durable Object storage. A successful
claim atomically deletes all active object storage, while an alarm deletes
abandoned session state after ten minutes. Refresh and revocation tokens also
pass through the Worker without being persisted. There is no user table or
long-term server-side credential store.

```
npx --yes wrangler@4.129.0 login
./deploy.sh
```

Worker name is `omarchy-oauth` so the hostname does not contain “coinbase”
(Coinbase rejects redirect URIs that do). Set the Coinbase app redirect URI
to `https://<worker>/oauth/callback`.

Routes:

- `POST /oauth/start` — create a session, return Coinbase authorize URL
- `GET /oauth/callback` — Coinbase redirect; exchange the code
- `POST /oauth/session` — one-time JSON token handoff using a random session ID
- `POST /oauth/refresh` — `{ "refresh_token": "..." }`
- `POST /oauth/revoke` — revoke the supplied access token on logout

Rate limits are not one global quota. Start and callback requests are limited by
source IP; session polling is limited by both source IP and random session; and
refresh/revocation are limited by both source IP and a SHA-256 token digest.
