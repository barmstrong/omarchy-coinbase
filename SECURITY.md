# Security policy

Security fixes are provided for the current release on the default branch.

Please report vulnerabilities privately through this repository's GitHub
Security tab. Do not include live Coinbase access tokens, refresh tokens,
authorization codes, client secrets, account balances, or other personal
financial data in an issue, screenshot, or log.

If a token may have been exposed, revoke the application's access from your
Coinbase account immediately and remove
`~/.local/state/omarchy/coinbase/tokens.json` before signing in again.

The plugin may add, remove, or reorder a single Simple Retail watchlist item after an
explicit user action, using `wallet:watchlist:update`. Read and update grants
are checked independently. Only the three fixed watchlist POST routes are used;
removal and reordering preserve the exact typed identities returned by GET.
Reordering moves one item relative to another without replacing the list or
removing unsupported items. Uncertain writes are not retried automatically.
The widget must not trade, transfer funds, or request additional write-capable
OAuth scopes. Disclosing credentials outside the explicitly configured OAuth
flow, or disclosing one user's OAuth result to another user, is a security
vulnerability.

Enabling the plugin separately installs the official `@coinbase/coinbase-cli`
using an exact version and npm lockfile integrity hashes, with package lifecycle
scripts disabled. Its local launcher and shared skill are reconciled without
overwriting existing user commands or skills. Setup may install Node 22 through
mise when needed. This installation is disclosed in the README and does not
configure authentication or grant trading permissions. The official CLI has
broader account capabilities when separately authenticated; the skill requires
user authorization for account mutations and never reuses widget OAuth tokens.

Local OAuth tokens, portfolio snapshots, account-derived watchlist data, and
cache files must remain owner-only (`0600`) inside the owner-only (`0700`)
state directory. Logout must clear bearer credentials and account-derived
caches before a signed-out snapshot is published. The retained
`market-snapshot.json` cache contains public market data only.
