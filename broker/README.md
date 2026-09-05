# Coinbase OAuth broker

Cloudflare Worker that holds your one Coinbase OAuth client secret so every
Omarchy installer can click Sign in.

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
- `GET /oauth/session/:id` — one-time token handoff for that random session ID
- `POST /oauth/refresh` — `{ "refresh_token": "..." }`
- `POST /oauth/revoke` — revoke the supplied access token on logout
