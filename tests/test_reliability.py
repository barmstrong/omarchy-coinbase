import contextlib
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import time
import unittest
from pathlib import Path


def load_helper():
    path = Path(__file__).resolve().parents[1] / "bin" / "coinbase"
    loader = importlib.machinery.SourceFileLoader("coinbase_reliability_helper", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def configure_state(helper, state):
    helper.STATE_DIR = state
    helper.APP_FILE = state / "oauth-app.json"
    helper.TOKEN_FILE = state / "tokens.json"
    helper.SNAPSHOT_FILE = state / "snapshot.json"
    helper.MARKET_SNAPSHOT_FILE = state / "market-snapshot.json"
    helper.WATCHLIST_FILE = state / "watchlist.json"
    helper.LOGIN_STATUS_FILE = state / "login-status.json"
    helper.PREFS_FILE = state / "prefs.json"
    helper.BROKER_URL_FILE = state / "broker.url"


class ReliabilityTests(unittest.TestCase):
    def test_signed_out_refresh_failure_keeps_complete_cache(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            cached = helper.empty_snapshot(
                period="day",
                catalogAt=int(time.time()),
                assets=[helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100)],
            )
            helper.write_snapshot(cached)
            helper.write_json(helper.MARKET_SNAPSHOT_FILE, cached)

            def offline(*_args, **_kwargs):
                raise RuntimeError("offline")

            helper.refresh_live_snapshot = offline
            result = helper.market_snapshot("day")

            self.assertEqual([row["id"] for row in result["assets"]], ["BTC"])
            stored = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
            self.assertEqual([row["id"] for row in stored["assets"]], ["BTC"])

    def test_authenticated_refresh_failure_keeps_complete_portfolio(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            cached = helper.empty_snapshot(
                authenticated=True,
                needsSetup=False,
                mode="portfolio",
                total=500,
                assets=[{"id": "BTC", "kind": "crypto", "held": True}],
            )
            helper.write_snapshot(cached)
            helper.valid_access_token = lambda: (_ for _ in ()).throw(RuntimeError("request failed: offline"))
            helper.market_snapshot = lambda *_args, **_kwargs: self.fail("must not switch to the signed-out view")

            result = helper.assemble_snapshot("day")

            self.assertTrue(result["authenticated"])
            self.assertEqual(result["total"], 500)
            stored = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
            self.assertTrue(stored["authenticated"])
            self.assertEqual(stored["total"], 500)

    def test_recent_snapshot_skips_duplicate_background_refresh(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            cached = helper.empty_snapshot(
                period="day",
                assets=[helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100)],
            )
            helper.write_snapshot(cached)
            helper.build_snapshot = lambda *_args, **_kwargs: self.fail("recent cache should be reused")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                helper.cmd_snapshot("day", max_age=20)

            self.assertEqual(json.loads(output.getvalue())["assets"][0]["id"], "BTC")

    def test_market_publish_updates_offline_cache_before_live_snapshot(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            helper.enrich_yahoo_assets = lambda _assets: None
            helper.apply_period_pnl = lambda _assets, _period, **_kwargs: ([95, 100], 5, 5.26)
            rows = [helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100)]

            result = helper.write_market_snapshot(rows, "day")

            self.assertEqual(result["assets"][0]["id"], "BTC")
            market = json.loads(helper.MARKET_SNAPSHOT_FILE.read_text(encoding="utf-8"))
            live = json.loads(helper.SNAPSHOT_FILE.read_text(encoding="utf-8"))
            self.assertEqual(market["assets"], live["assets"])
            self.assertEqual(helper.MARKET_SNAPSHOT_FILE.stat().st_mode & 0o777, 0o600)

    def test_partial_market_response_is_filled_from_cached_catalog(self):
        helper = load_helper()
        fresh = [helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=100)]
        previous = helper.empty_snapshot(
            assets=[
                helper.market_row("BTC", "Bitcoin", "crypto", "BTC-USD", price=99),
                helper.market_row("ETH", "Ethereum", "crypto", "ETH-USD", price=10),
                helper.market_row("AAPL", "Apple", "stock", "AAPL-USD", price=200),
            ]
        )

        merged = helper.merge_missing_market_categories(fresh, previous)

        self.assertEqual([row["id"] for row in merged], ["BTC", "ETH", "AAPL"])
        self.assertEqual(merged[0]["price"], 100)


if __name__ == "__main__":
    unittest.main()
