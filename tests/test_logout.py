import contextlib
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path


def load_helper():
    path = Path(__file__).resolve().parents[1] / "bin" / "coinbase"
    loader = importlib.machinery.SourceFileLoader("coinbase_helper", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class LogoutTests(unittest.TestCase):
    def test_login_publishes_authenticated_state_before_full_snapshot(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            helper.STATE_DIR = state
            helper.TOKEN_FILE = state / "tokens.json"
            helper.SNAPSHOT_FILE = state / "snapshot.json"
            helper.MARKET_SNAPSHOT_FILE = state / "market-snapshot.json"
            helper.WATCHLIST_FILE = state / "watchlist.json"
            helper.LOGIN_STATUS_FILE = state / "login-status.json"
            helper.PREFS_FILE = state / "prefs.json"
            helper.BROKER_URL_FILE = state / "broker.url"
            helper.BROKER_URL_FILE.write_text("https://broker.example\n", encoding="utf-8")
            helper.load_prefs = lambda: {"period": "week"}
            public = helper.empty_snapshot(
                period="week",
                assets=[helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100)],
            )
            helper.write_snapshot(public)

            full_snapshot_started = False

            def fake_build_snapshot(period, *, publish_loading=False):
                nonlocal full_snapshot_started
                full_snapshot_started = True
                self.assertTrue(publish_loading)
                self.assertEqual(period, "week")
                snapshot = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
                self.assertTrue(snapshot["authenticated"])
                self.assertTrue(snapshot["loading"])
                self.assertEqual(snapshot["assets"], [])
                self.assertEqual(snapshot["period"], "week")
                status = json.loads(helper.LOGIN_STATUS_FILE.read_text(encoding="utf-8"))
                self.assertEqual(status["status"], "snapshot")
                helper.write_snapshot(
                    helper.empty_snapshot(
                        authenticated=True,
                        needsSetup=False,
                        period=period,
                        mode="portfolio",
                        total=250,
                        assets=[{"id": "BTC", "kind": "crypto", "held": True}],
                    )
                )

            helper.build_snapshot = fake_build_snapshot
            with contextlib.redirect_stdout(io.StringIO()):
                helper._finish_login(
                    {
                        "access_token": "access",
                        "refresh_token": "refresh",
                        "expires_in": 3600,
                    }
                )

            self.assertTrue(full_snapshot_started)
            snapshot = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
            self.assertTrue(snapshot["authenticated"])
            self.assertEqual(snapshot["total"], 250)
            status = json.loads(helper.LOGIN_STATUS_FILE.read_text(encoding="utf-8"))
            self.assertEqual(status["status"], "done")

    def test_login_publishes_balance_before_slow_enrichment(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            helper.STATE_DIR = state
            helper.SNAPSHOT_FILE = state / "snapshot.json"
            helper.MARKET_SNAPSHOT_FILE = state / "market-snapshot.json"
            helper.WATCHLIST_FILE = state / "watchlist.json"
            helper.LOGIN_STATUS_FILE = state / "login-status.json"
            helper.PREFS_FILE = state / "prefs.json"
            helper.BROKER_URL_FILE = state / "broker.url"
            helper.BROKER_URL_FILE.write_text("https://broker.example\n", encoding="utf-8")
            helper.valid_access_token = lambda: "token"
            helper.token_is_current = lambda _token: True
            helper.fetch_user = lambda _token: {"name": "Test"}
            holding = {"id": "BTC", "kind": "crypto", "value": 250, "held": True}
            helper.fetch_breakdown = lambda _token: ([holding], 250)

            def observe_loading(assets, _token):
                loading = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
                self.assertTrue(loading["authenticated"])
                self.assertTrue(loading["loading"])
                self.assertEqual(loading["total"], 250)
                self.assertEqual(loading["user"], {})
                return assets

            helper.merge_watchlist = observe_loading
            helper.enrich_with_products = lambda _assets: None
            helper.tidy_assets = lambda assets: assets
            helper.market_assets = lambda: []
            helper.merge_missing_market_categories = lambda rows, _previous: rows
            helper.enrich_yahoo_assets = lambda _assets: None
            helper.resolve_stock_holdings = lambda _assets: None
            helper.dedupe_stock_assets = lambda assets: assets
            helper.restore_row_spark_cache = lambda _assets, _previous: None
            helper.activate_cached_row_sparks = lambda _assets, _period: None
            helper.apply_period_pnl = lambda _assets, _period: ([200, 250], 50, 25)
            helper.fill_crypto_row_sparks = lambda _assets, _period: None
            helper.refresh_products_cache = lambda: None

            result = helper.assemble_snapshot("day", publish_loading=True)

            self.assertFalse(result.get("loading", False))
            self.assertEqual(result["total"], 250)
            self.assertEqual(result["user"]["name"], "Test")

    def test_logout_clears_private_snapshot_before_network_work(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            helper.STATE_DIR = state
            helper.APP_FILE = state / "oauth-app.json"
            helper.TOKEN_FILE = state / "tokens.json"
            helper.SNAPSHOT_FILE = state / "snapshot.json"
            helper.MARKET_SNAPSHOT_FILE = state / "market-snapshot.json"
            helper.WATCHLIST_FILE = state / "watchlist.json"
            helper.LOGIN_STATUS_FILE = state / "login-status.json"
            helper.BROKER_URL_FILE = state / "broker.url"
            helper.BROKER_URL_FILE.write_text("https://broker.example\n", encoding="utf-8")
            helper.load_prefs = lambda: {"period": "week"}

            helper.write_json(
                helper.TOKEN_FILE,
                {"access_token": "private-token", "refresh_token": "private-refresh"},
                private=True,
            )
            helper.write_snapshot(
                helper.empty_snapshot(
                    authenticated=True,
                    error="stale OAuth error",
                    user={"name": "Private User"},
                    assets=[{"id": "PRIVATE"}],
                    total=123,
                )
            )
            helper.write_json(
                helper.WATCHLIST_FILE,
                {"coinbase": [{"id": "PRIVATE", "watchlist": True}], "coinbaseAt": 1},
            )
            public_rows = [
                helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100),
                helper.market_row("ETH", "Ethereum", "crypto", "ETH-USD", price=10),
            ]
            public_snapshot = helper.empty_snapshot(
                authenticated=False,
                mode="market",
                period="week",
                assets=public_rows,
            )
            public_snapshot["bar"]["period"] = "week"
            helper.write_json(helper.MARKET_SNAPSHOT_FILE, public_snapshot)

            revoke_checked = False

            def fake_http_json(method, url, **_kwargs):
                nonlocal revoke_checked
                revoke_checked = True
                self.assertEqual(method, "POST")
                self.assertEqual(url, "https://broker.example/oauth/revoke")
                self.assertFalse(helper.TOKEN_FILE.exists())
                snapshot = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
                self.assertFalse(snapshot["authenticated"])
                self.assertEqual(snapshot["error"], "")
                self.assertEqual([row["id"] for row in snapshot["assets"]], ["BTC", "ETH"])
                self.assertEqual(snapshot["user"], {})
                self.assertEqual(snapshot["period"], "week")
                self.assertEqual(snapshot["bar"]["period"], "week")
                status = json.loads(helper.LOGIN_STATUS_FILE.read_text(encoding="utf-8"))
                self.assertEqual(status["status"], "logged-out")
                self.assertFalse(helper.WATCHLIST_FILE.exists())
                raise RuntimeError("simulated offline revoke")

            market_refreshed = False

            def fake_market_snapshot(period):
                nonlocal market_refreshed
                market_refreshed = True
                self.assertEqual(period, "week")
                helper.write_snapshot(
                    helper.empty_snapshot(
                        authenticated=False,
                        mode="market",
                        period=period,
                        assets=public_rows,
                    )
                )

            helper.http_json = fake_http_json
            helper.market_snapshot = fake_market_snapshot
            with contextlib.redirect_stdout(io.StringIO()):
                helper.cmd_logout()

            self.assertTrue(revoke_checked)
            self.assertTrue(market_refreshed)
            self.assertFalse(helper.token_is_current("private-token"))
            final_snapshot = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
            self.assertFalse(final_snapshot["authenticated"])
            self.assertEqual(final_snapshot["mode"], "market")
            self.assertEqual([row["id"] for row in final_snapshot["assets"]], ["BTC", "ETH"])
            self.assertFalse(any(row["watchlist"] for row in final_snapshot["assets"]))

    def test_state_files_are_owner_only(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            helper.STATE_DIR = state
            helper.SNAPSHOT_FILE = state / "snapshot.json"
            helper.MARKET_SNAPSHOT_FILE = state / "market-snapshot.json"
            helper.write_snapshot({"authenticated": False})
            self.assertEqual(helper.SNAPSHOT_FILE.stat().st_mode & 0o777, 0o600)

    def test_rejects_token_with_unrequested_scope(self):
        helper = load_helper()
        with self.assertRaisesRegex(RuntimeError, "outside this read-only app"):
            helper.validate_token_grant(
                {
                    "access_token": "access",
                    "token_type": "bearer",
                    "scope": "wallet:accounts:read,wallet:transactions:send",
                }
            )


if __name__ == "__main__":
    unittest.main()
