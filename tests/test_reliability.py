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
    helper.DETAIL_CACHE_FILE = state / "detail-cache.json"
    helper.BROKER_URL_FILE = state / "broker.url"


class ReliabilityTests(unittest.TestCase):
    def test_future_products_are_classified_by_underlying(self):
        helper = load_helper()

        def product(underlying):
            return {
                "product_type": "FUTURE",
                "future_product_details": {
                    "perpetual_details": {"underlying_type": underlying}
                },
            }

        self.assertEqual(helper.market_category_for_product(product("SPOT")), "crypto")
        self.assertEqual(helper.market_category_for_product(product("EQUITY")), "stock")
        self.assertEqual(helper.market_category_for_product(product("EQUITY_ETF")), "stock")
        self.assertEqual(helper.market_category_for_product(product("COMMOD")), "commodity")
        self.assertEqual(helper.market_category_for_product(product("INDEX")), "index")
        self.assertEqual(helper.market_category_for_product(product("PREIPO")), "preipo")

    def test_fcm_products_are_classified_by_asset_type_and_group(self):
        helper = load_helper()

        def product(asset_type, group="", trading_hours_type=""):
            return {
                "product_type": "FUTURE",
                "display_name": "TEST PERP",
                "future_product_details": {
                    "futures_asset_type": asset_type,
                    "group_description": group,
                    "trading_hours_type": trading_hours_type,
                },
            }

        self.assertEqual(
            helper.market_category_for_product(
                product("FUTURES_ASSET_TYPE_STOCKS", "AI Index Perp Style Futures")
            ),
            "index",
        )
        self.assertEqual(
            helper.market_category_for_product(
                product("FUTURES_ASSET_TYPE_STOCKS", "Mag7+Crypto Futures")
            ),
            "index",
        )
        self.assertEqual(
            helper.market_category_for_product(
                product(
                    "FUTURES_ASSET_TYPE_STOCKS",
                    "Tech100 Perp Style Futures",
                    "TRADING_HOURS_TYPE_EQUITY_INDEX",
                )
            ),
            "index",
        )
        self.assertEqual(
            helper.market_category_for_product(product("FUTURES_ASSET_TYPE_STOCKS")),
            "stock",
        )
        self.assertEqual(
            helper.market_category_for_product(product("FUTURES_ASSET_TYPE_METALS")),
            "commodity",
        )
        self.assertEqual(
            helper.market_category_for_product(product("FUTURES_ASSET_TYPE_ENERGY")),
            "commodity",
        )
        self.assertEqual(
            helper.market_category_for_product(product("FUTURES_ASSET_TYPE_CRYPTO")),
            "crypto",
        )

    def test_crypto_tab_only_matches_spot_crypto(self):
        helper = load_helper()
        spot = {"kind": "crypto", "marketCategory": "crypto"}
        perp = {"kind": "derivative", "marketCategory": "crypto"}

        self.assertTrue(helper.asset_matches_market_tab(spot, "crypto"))
        self.assertFalse(helper.asset_matches_market_tab(perp, "crypto"))
        self.assertTrue(helper.asset_matches_market_tab(perp, "all"))

    def test_market_catalog_dedupes_by_coinbase_product_id(self):
        helper = load_helper()
        portfolio_row = {
            "id": "TEK-19DEC30-CDE",
            "kind": "derivative",
            "productId": "TEK-19DEC30-CDE",
            "held": True,
            "marketCategory": "crypto",
        }
        duplicate_portfolio_row = dict(portfolio_row)
        catalog_row = {
            "id": "TECH",
            "kind": "derivative",
            "productId": "TEK-19DEC30-CDE",
            "held": False,
            "marketCategory": "index",
        }
        other_expiry = {
            "id": "TECH DEC 31",
            "kind": "derivative",
            "productId": "TEK-19DEC31-CDE",
            "held": False,
        }

        rows = helper.append_missing_market_assets(
            [portfolio_row, duplicate_portfolio_row], [catalog_row, other_expiry]
        )

        self.assertEqual(rows, [portfolio_row, other_expiry])
        self.assertEqual(rows[0]["marketCategory"], "index")
        self.assertTrue(rows[0]["held"])

    def test_derivative_catalog_merges_intx_and_fcm_products(self):
        helper = load_helper()
        calls = []
        shared = {
            "product_id": "COIN50-PERP-INTX",
            "display_name": "Coinbase 50 Index PERP",
            "price": "100",
            "approximate_quote_24h_volume": "50",
            "future_product_details": {
                "perpetual_details": {"underlying_type": "INDEX"}
            },
        }
        fcm = {
            "product_id": "AIP-19DEC30-CDE",
            "display_name": "AI PERP",
            "price": "200",
            "approximate_quote_24h_volume": "100",
            "future_product_details": {
                "futures_asset_type": "FUTURES_ASSET_TYPE_STOCKS",
                "group_description": "AI Index Perp Style Futures",
            },
        }

        def fake_fetch(product_type, extra):
            calls.append((product_type, extra))
            if extra.get("contract_expiry_type") == "PERPETUAL":
                return [shared]
            return [fcm, shared]

        helper.fetch_typed_products = fake_fetch
        rows = helper.derivative_majors()

        self.assertEqual(
            calls,
            [
                ("FUTURE", {"contract_expiry_type": "PERPETUAL"}),
                ("FUTURE", {"expiring_contract_status": "STATUS_UNEXPIRED"}),
            ],
        )
        self.assertEqual([row["productId"] for row in rows], ["AIP-19DEC30-CDE", "COIN50-PERP-INTX"])
        self.assertTrue(all(row["marketCategory"] == "index" for row in rows))

    def test_public_product_catalog_follows_pagination(self):
        helper = load_helper()
        calls = []

        def fake_public_get(_path, params):
            calls.append(dict(params))
            if len(calls) == 1:
                return {
                    "products": [{"product_id": "BTC-PERP-INTX"}],
                    "pagination": {"has_next": True, "next_cursor": "next"},
                }
            return {
                "products": [{"product_id": "GOLD-PERP-INTX"}],
                "pagination": {"has_next": False},
            }

        helper.public_get = fake_public_get
        rows = helper.fetch_typed_products("FUTURE", {"contract_expiry_type": "PERPETUAL"})

        self.assertEqual([row["product_id"] for row in rows], ["BTC-PERP-INTX", "GOLD-PERP-INTX"])
        self.assertEqual(calls[0]["limit"], 250)
        self.assertEqual(calls[1]["cursor"], "next")

    def test_row_sparklines_are_batched_within_selected_category(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            helper.load_prefs = lambda: {"period": "day"}
            rows = [
                helper.market_row(
                    f"C{i}",
                    f"Commodity {i}",
                    "derivative",
                    f"C{i}-PERP-INTX",
                    price=100 + i,
                    marketCategory="commodity",
                    volume24h=i,
                )
                for i in range(30)
            ]
            rows.append(
                helper.market_row(
                    "BTC", "Bitcoin", "crypto", "BTC-USD", price=100, volume24h=1_000_000
                )
            )
            helper.write_snapshot(helper.empty_snapshot(period="day", assets=rows))
            fetched = []

            def fake_fill(targets, period):
                self.assertEqual(period, "day")
                fetched.extend(targets)

            helper.fill_period_row_sparks = fake_fill
            with contextlib.redirect_stdout(io.StringIO()):
                helper.cmd_rows("day", "commodity")

            self.assertEqual(len(fetched), helper.ROW_SPARK_BATCH)
            self.assertTrue(all(row["marketCategory"] == "commodity" for row in fetched))
            self.assertEqual(fetched[0]["id"], "C29")

    def test_recent_detail_cache_skips_network_refresh(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            cached = {
                "id": "BTC",
                "kind": "crypto",
                "productId": "BTC-USD",
                "period": "week",
                "price": 100,
                "sparkline": [90, 100],
                "stats": [{"label": "RANK", "value": "#1"}],
            }
            helper.store_detail("BTC-USD", "BTC", "crypto", "week", cached)
            helper.build_chart_data = lambda *_args: self.fail("fresh detail cache should be reused")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                helper.cmd_chart("BTC-USD", "week", "BTC", "crypto")

            self.assertEqual(json.loads(output.getvalue()), cached)

    def test_stale_detail_cache_survives_failed_refresh(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            cached = {
                "id": "ETH",
                "kind": "crypto",
                "productId": "ETH-USD",
                "period": "day",
                "price": 100,
                "sparkline": [90, 95, 100],
                "stats": [],
            }
            helper.store_detail("ETH-USD", "ETH", "crypto", "day", cached)
            raw = json.loads(helper.DETAIL_CACHE_FILE.read_text(encoding="utf-8"))
            key = helper.detail_cache_key("ETH-USD", "ETH", "crypto", "day")
            raw["entries"][key]["fetchedAt"] = int(time.time()) - helper.DETAIL_CACHE_TTL - 1
            helper.write_json(helper.DETAIL_CACHE_FILE, raw)
            helper.build_chart_data = lambda *_args: {
                "id": "ETH",
                "kind": "crypto",
                "productId": "ETH-USD",
                "period": "day",
                "price": 0,
                "sparkline": [],
                "stats": [],
            }

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                helper.cmd_chart("ETH-USD", "day", "ETH", "crypto")

            self.assertEqual(json.loads(output.getvalue()), cached)

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

    def test_loading_portfolio_stops_spinning_on_auth_failure(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            helper.write_snapshot(helper.portfolio_loading_snapshot("day", total=250))

            def fail_auth():
                raise RuntimeError("refresh unavailable")

            helper.valid_access_token = fail_auth
            result = helper.assemble_snapshot("day")

            self.assertTrue(result["authenticated"])
            self.assertNotIn("loading", result)
            self.assertEqual(result["total"], 250)
            self.assertEqual(result["error"], "refresh unavailable")

    def test_advanced_watchlist_uses_supported_product_flags_in_api_order(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            configure_state(helper, state)
            products = {
                "SPOT": [{"product_id": "BTC-USD"}, {"product_id": "ETH-USD"}],
                "EQUITY": [{"product_id": "COIN-USD"}],
                "FUTURE": [{"product_id": "BTC-PERP"}],
            }
            helper.fetch_auth_products = lambda _token, product_type, _extra: products[product_type]
            helper.slim_watch_entry = lambda product: {
                "id": product["product_id"],
                "kind": "test",
                "productId": product["product_id"],
            }

            result = helper.fetch_advanced_watchlist("token", force=True)

            self.assertEqual(
                [row["id"] for row in result],
                ["BTC-USD", "ETH-USD", "COIN-USD", "BTC-PERP"],
            )
            cached = json.loads(helper.WATCHLIST_FILE.read_text(encoding="utf-8"))
            self.assertEqual(cached["advanced"], result)
            self.assertNotIn("coinbase", cached)

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
