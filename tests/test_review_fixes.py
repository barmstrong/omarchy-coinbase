import contextlib
import fcntl
import io
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from test_reliability import configure_state, load_helper


class ReviewFixTests(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        configure_state(self.helper, Path(self.directory.name))

    def test_optional_watchlist_grant_is_accepted_but_transfers_are_not(self):
        h = self.helper
        h.validate_token_grant({"scope": "wallet:user:read wallet:accounts:read wallet:watchlist:read wallet:watchlist:update offline_access", "token_type": "bearer"})
        for scope in ("wallet:transactions:send", "wallet:buys:create", "wallet:accounts:update"):
            with self.assertRaises(RuntimeError):
                h.validate_token_grant({"scope": scope})

    def test_token_refresh_error_is_published_without_freshening_balances(self):
        h = self.helper
        before = h.empty_snapshot(authenticated=True, total=500, fetchedAt="2020-01-01T00:00:00Z", assets=[{"id": "BTC"}])
        h.write_snapshot(before)
        with patch.object(h, "valid_access_token", side_effect=RuntimeError("offline")):
            result = h.assemble_snapshot("day")
        self.assertEqual(result["error"], "offline")
        self.assertEqual(result["fetchedAt"], before["fetchedAt"])
        self.assertEqual(result["total"], 500)
        self.assertGreater(result["retryAfter"], time.time())
        self.assertEqual(h.read_json(h.SNAPSHOT_FILE, {}), result)

    def test_snapshot_mtime_does_not_make_old_balances_fresh(self):
        h = self.helper
        old = h.empty_snapshot(fetchedAt="2020-01-01T00:00:00Z", assets=[{"id": "BTC"}])
        h.write_snapshot(old)  # New mtime, old data.
        with patch.object(h, "build_snapshot", return_value=old) as build, contextlib.redirect_stdout(io.StringIO()):
            h.cmd_snapshot("day", max_age=20)
        build.assert_called_once_with("day")

    def test_failure_backoff_and_manual_retry(self):
        h = self.helper
        old = h.empty_snapshot(fetchedAt="2020-01-01T00:00:00Z", assets=[{"id": "BTC"}])
        h.failed_snapshot(old, "offline")
        with patch.object(h, "build_snapshot", return_value=old) as build, contextlib.redirect_stdout(io.StringIO()):
            h.cmd_snapshot("day", max_age=20)
            build.assert_not_called()
            h.cmd_snapshot("day")
            build.assert_called_once()

    def test_background_refresh_never_waits_for_another_writer(self):
        h = self.helper
        h._BACKGROUND_JOB = True
        with (h.STATE_DIR / "snapshot.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with self.assertRaises(h.RefreshBusy), h.snapshot_lock():
                self.fail("lock was acquired twice")
        with h.snapshot_lock():
            pass

    def test_partial_watchlist_failure_preserves_failed_category(self):
        h = self.helper
        h.save_watchlist_state(advanced=[{"id": "BTC", "kind": "crypto"}, {"id": "COIN", "kind": "stock"}], advancedAt=1)
        with patch.object(h, "fetch_auth_products", side_effect=lambda token, kind, extra: None if kind == "SPOT" else []):
            result = h.fetch_advanced_watchlist("synthetic", force=True)
        self.assertEqual([row["id"] for row in result], ["BTC"])
        self.assertEqual(h.load_watchlist_state()["advancedAt"], 0)

    def test_valid_empty_watchlist_is_cached(self):
        h = self.helper
        h.save_watchlist_state(advanced=[], advancedAt=int(time.time()))
        with patch.object(h, "fetch_auth_products") as fetch:
            self.assertEqual(h.fetch_advanced_watchlist("synthetic"), [])
        fetch.assert_not_called()

    def test_failure_on_later_watchlist_page_is_not_a_complete_result(self):
        h = self.helper
        first = {"products": [{"product_id": "BTC-USD", "watched": True}], "pagination": {"has_next": True, "next_cursor": "next"}}
        with patch.object(h, "api_get", side_effect=[first, RuntimeError("offline")]):
            self.assertIsNone(h.fetch_auth_products("synthetic", "SPOT"))
        with patch.object(h, "api_get", return_value=first):
            self.assertIsNone(h.fetch_auth_products("synthetic", "SPOT", max_pages=1))

    def test_watchlist_pagination_continues_past_unwatched_page(self):
        h = self.helper
        pages = [
            {"products": [{"product_id": "ETH-USD"}], "pagination": {"has_next": True}},
            {"products": [{"product_id": "SOL-USD"}], "pagination": {"has_next": True}},
            {"products": [{"product_id": "BTC-USD", "watched": True}], "pagination": {"has_next": False}},
        ]
        with patch.object(h, "api_get", side_effect=pages):
            self.assertEqual(h.fetch_auth_products("synthetic", "SPOT", limit=1)[0]["product_id"], "BTC-USD")

    def test_candle_batch_writes_once_and_preserves_other_process_updates(self):
        h = self.helper
        h.write_json(h.CANDLES_CACHE, {"existing": {"candles": [[1, 2]], "fetchedAt": 1}})
        with patch.object(h, "write_json", wraps=h.write_json) as write:
            with h.candle_batch():
                self.assertEqual(h._cached_candles("existing")[0], [(1, 2)])
                h._store_cached_candles("one", [(2, 3)])
                h._store_cached_candles("two", [(3, 4)])
                self.assertEqual(h._cached_candles("one")[0], [(2, 3)])
                write.assert_not_called()
                # Another command updates a different entry before our merge.
                with h.CANDLES_CACHE.open("w") as stream:
                    json.dump({"other": {"candles": [[4, 5]], "fetchedAt": 1}}, stream)
            self.assertEqual(write.call_count, 1)
        self.assertEqual(set(h.read_json(h.CANDLES_CACHE, {})), {"one", "two", "other"})


if __name__ == "__main__":
    unittest.main()
