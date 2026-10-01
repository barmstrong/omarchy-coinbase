---
name: coinbase-cli
description: Use the official Coinbase CLI for Coinbase account balances, portfolios, market data, and user-requested account operations from a local terminal. Applies to the Coinbase platform, not unrelated wallets or exchanges.
---

# Coinbase CLI on Omarchy

The official `@coinbase/coinbase-cli` package is available as `coinbase` on PATH
(or `~/.local/bin/coinbase`). The Omarchy Coinbase plugin's private
`~/.config/omarchy/plugins/coinbase/bin/coinbase` is a different program; do not
substitute it for the official CLI.

Start with `coinbase --help` and the relevant command's `--help`. Commands
return JSON; use `--jq` when only a few fields are needed. Useful reads:

```sh
coinbase --version
coinbase env
coinbase balance
coinbase portfolios list
coinbase portfolios get <portfolio_id>
coinbase products get BTC-USD
```

The official CLI uses its own configured credentials. The widget's OAuth login
does not authenticate this CLI. Reuse an existing CLI environment. If none is
configured, explain the required account connection and use the current
[official setup instructions](https://docs.cdp.coinbase.com/coinbase-cli/skill.md).
Do not read or copy the widget's tokens, request secrets in chat, or put secrets
in command arguments. The documented CLI setup supports `coinbase env live
--key-file <path-to-key.json>` and Linux keyring storage through `secret-tool`.

Installation or a balance inquiry does not authorize trading, transfers, paid
data requests, or changes to the account. For user-requested writes, establish
the exact action, portfolio, asset, and amount; inspect the command help and
use `--template` or `--dry-run` as appropriate. Honor the user's existing
specific authorization. If a write times out, check its outcome before trying
again; do not duplicate an uncertain order or payment.

Portfolio figures from the widget are not guaranteed to match the website:
the widget currently reads one portfolio and estimates period change from
current holdings. For account-wide inquiries, enumerate the relevant portfolios
and state the scope and timestamp of the returned data.

If installation needs repair, run:

```sh
python3 ~/.config/omarchy/plugins/coinbase/bin/setup-agents ensure
python3 ~/.config/omarchy/plugins/coinbase/bin/setup-agents status
```

Skills become discoverable on the agent's next skill reload or new session.
A locally installed CLI is not automatically available to remote sandboxes.
