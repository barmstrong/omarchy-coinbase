# Security policy

Security fixes are provided for the current release on the default branch.

Please report vulnerabilities privately through this repository's GitHub
Security tab. Do not include live Coinbase access tokens, refresh tokens,
authorization codes, client secrets, account balances, or other personal
financial data in an issue, screenshot, or log.

If a token may have been exposed, revoke the application's access from your
Coinbase account immediately and remove
`~/.local/state/omarchy/coinbase/tokens.json` before signing in again.

The plugin does not mutate account data. The helper permits the optional
`wallet:watchlist:read` and `wallet:watchlist:update` grant for future watchlist
testing, but does not call the experimental endpoint or expose mutation UI.
Any behavior that can trade, transfer funds, request other write-capable OAuth scopes, send Coinbase credentials
to a non-Coinbase API, or disclose one user's OAuth result to another user is a
security vulnerability.

Local OAuth tokens, portfolio snapshots, account-derived watchlist data, and
cache files must remain owner-only (`0600`) inside the owner-only (`0700`)
state directory. Logout must clear bearer credentials and account-derived
caches before a signed-out snapshot is published. The retained
`market-snapshot.json` cache contains public market data only.
