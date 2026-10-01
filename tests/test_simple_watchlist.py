import tempfile
import contextlib
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from test_reliability import configure_state, load_helper


class SimpleWatchlistTests(unittest.TestCase):
    def test_reorder_uses_single_canonical_item_and_anchor(self):
        h = self.h
        item = {"tokenCbrn": "v1:token:base:mainnet:0xtest:"}
        anchor = {"equityCbrn": "v1:equity:::stock-coin:"}
        for direction in ("beforeItem", "afterItem"):
            with self.subTest(direction=direction), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "crypto_asset_catalog", side_effect=AssertionError("no resolution needed")):
                h.mutate_simple_watchlist("synthetic", "reorder", item, position={direction: anchor})
            self.assertEqual(post.call_args.args, ("POST", h.API + "/v2/watchlist/items/reorder"))
            self.assertEqual(post.call_args.kwargs["body"], {"item": item, direction: anchor})
            post.assert_called_once()

    def test_reorder_rejects_missing_double_invalid_and_self_anchors(self):
        h = self.h
        item = {"equityCbrn": "v1:equity:::coin:"}
        other = {"equityCbrn": "v1:equity:::other:"}
        for position in (None, {}, {"beforeItem": other, "afterItem": other}, {"beforeItem": item},
                         {"afterItem": {}}, {"beforeItem": {"assetUuid": "invalid"}},
                         {"index": 1}, {"beforeItem": {"equityCbrn": "a", "tokenCbrn": "b"}}):
            with self.subTest(position=position), patch.object(h, "http_json") as post, self.assertRaises(RuntimeError):
                h.mutate_simple_watchlist("synthetic", "reorder", item, position=position)
            post.assert_not_called()

    def test_read_only_scope_cannot_reorder(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:read"}
        with patch.object(h, "http_json") as post, self.assertRaises(RuntimeError):
            h.mutate_simple_watchlist("synthetic", "reorder", {"equityCbrn": "a"}, position={"afterItem": {"equityCbrn": "b"}})
        post.assert_not_called()

    def test_reorder_command_preserves_hidden_items_and_reads_server_order(self):
        h = self.h
        item, anchor = {"equityCbrn": "v1:equity:::stock-coin:"}, {"assetUuid": "11111111-1111-1111-1111-111111111111"}
        hidden = {"predictionCbrn": "v1:derivative:kalshi:event:hidden:"}
        items = [hidden, item, anchor]
        h.write_snapshot(h.empty_snapshot(authenticated=True, assets=[]))
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "api_get", return_value={"items": items}) as get, patch("sys.stdin", io.StringIO(json.dumps({"item": item, "beforeItem": anchor}))), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("reorder")
        result = json.loads(out.getvalue())
        self.assertTrue(result["ok"])
        self.assertEqual(result["items"], items)
        self.assertEqual(h.load_watchlist_state()["simpleItems"], items)
        self.assertEqual(h.read_json(h.SNAPSHOT_FILE, {})["watchlistStatus"]["items"], items)
        self.assertEqual(post.call_args.kwargs["body"], {"item": item, "beforeItem": anchor})
        post.assert_called_once()
        get.assert_called_once_with(h.WATCHLIST_PATH, "synthetic")

    def test_reorder_read_failure_never_retries_acknowledged_move(self):
        h = self.h
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "api_get", side_effect=RuntimeError("offline")), patch("sys.stdin", io.StringIO('{"item":{"equityCbrn":"a"},"afterItem":{"equityCbrn":"b"}}')), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("reorder")
        result = json.loads(out.getvalue())
        self.assertTrue(result["ok"])
        self.assertNotIn("items", result)
        self.assertIn("Refresh pending", result["message"])
        post.assert_called_once()

    def test_update_only_reorder_does_not_read(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:update"}
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "api_get") as get, patch("sys.stdin", io.StringIO('{"item":{"equityCbrn":"a"},"beforeItem":{"equityCbrn":"b"}}')), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("reorder")
        post.assert_called_once()
        get.assert_not_called()
        self.assertTrue(json.loads(out.getvalue())["ok"])

    def test_reorder_rejects_extra_payload_fields(self):
        h = self.h
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json") as post, patch("sys.stdin", io.StringIO('{"item":{"equityCbrn":"a"},"beforeItem":{"equityCbrn":"b"},"watchlistId":"other"}')), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("reorder")
        post.assert_not_called()
        self.assertFalse(json.loads(out.getvalue())["ok"])

    def setUp(self):
        self.h = load_helper()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        configure_state(self.h, Path(self.tmp.name))
        self.h.granted_scopes = lambda: {"wallet:watchlist:read", "wallet:watchlist:update"}
        self.h.token_is_current = lambda token: True
        self.h.crypto_asset_catalog = lambda: [{"assetUuid": "asset-btc", "id": "BTC", "name": "Bitcoin"}]
        self.real_load_equity_index = self.h.load_equity_index
        self.h.load_equity_index = lambda: [{"productId": "stock-coin", "ticker": "COIN", "name": "Coinbase"}]

    def test_equity_catalog_reads_past_old_page_cap_and_keeps_aliases(self):
        h = self.h
        pages = [{"products": [], "pagination": {"has_next": True, "next_cursor": str(i)}} for i in range(13)]
        pages[0]["products"] = [{"product_id": "coin-usdc", "alias": "coin-usd", "equity_product_details": {"ticker": "COIN"}}]
        pages.append({"products": [{"product_id": "coin-usd", "equity_product_details": {"ticker": "COIN"}},
                                   {"product_id": "micron-usd", "equity_product_details": {"ticker": "MU"}}]})
        h.write_json(h.PRODUCTS_CACHE, {"equityIndex": [{"ticker": "OLD"}], "equityIndexFetchedAt": h.time.time()})
        with patch.object(h, "public_get", side_effect=pages) as get:
            rows = self.real_load_equity_index()
        self.assertEqual(get.call_count, 14)
        self.assertEqual([row["ticker"] for row in rows], ["COIN", "MU"])
        self.assertEqual(set(rows[0]["productAliases"]), {"coin-usd", "coin-usdc"})
        with patch.object(h, "public_get", side_effect=AssertionError("must use complete cache")):
            self.assertEqual(self.real_load_equity_index(), rows)

    def test_partial_equity_catalog_does_not_overwrite_complete_cache(self):
        h = self.h
        old = [{"ticker": "COIN", "productId": "coin"}]
        h.write_json(h.PRODUCTS_CACHE, {"equityIndex": old, "equityIndexFetchedAt": 1, "equityIndexVersion": 2})
        with patch.object(h, "public_get", side_effect=[{"products": [], "pagination": {"has_next": True, "next_cursor": "more"}}, RuntimeError("offline")]):
            self.assertEqual(self.real_load_equity_index(), old)
        self.assertEqual(h.read_json(h.PRODUCTS_CACHE, {})["equityIndex"], old)

    def test_equity_alias_roundtrip_shows_stock_and_uses_canonical_remove_id(self):
        h = self.h
        h.load_equity_index = lambda: [{"productId": "coin-usdc", "productAliases": ["coin-usd"], "ticker": "COIN", "name": "Coinbase"}]
        item = {"equityCbrn": "v1:equity:::coin-usd:"}
        row = {"kind": "stock", "id": "COIN", "productId": "coin-usdc"}
        self.assertEqual(h.watchlist_reference(row), {"equityProductId": "coin-usdc"})
        with patch.object(h, "api_get", return_value={"items": [item]}):
            entries = h.fetch_simple_watchlist("synthetic", force=True)
        self.assertEqual(entries[0]["id"], "COIN")
        self.assertTrue(h.merge_watchlist_entries([dict(row)], entries)[0]["watchlist"])
        # Also works when an already-open detail page uses the USD listing.
        state = h.watchlist_action_state({**row, "productId": "coin-usd"})
        self.assertTrue(state["watched"])
        self.assertEqual(state["item"], item)
        with patch.object(h, "http_json", return_value={}) as post:
            h.mutate_simple_watchlist("synthetic", "remove", state["item"])
        self.assertEqual(post.call_args.kwargs["body"], {"item": item})

    def test_exact_equity_detail_fallback_is_cached_and_validated(self):
        h = self.h
        pid = "a" * 64
        item = {"equityCbrn": "v1:equity:::" + pid + ":"}
        product = {"product_id": pid, "product_type": "EQUITY", "equity_product_details": {"ticker": "MU", "short_name": "Micron"}}
        with patch.object(h, "fetch_product", return_value=product) as get:
            rows = h.parse_simple_watchlist({"items": [item]})
            self.assertEqual(h.parse_simple_watchlist({"items": [item]}), rows)
        get.assert_called_once_with(pid)
        self.assertEqual(rows[0]["id"], "MU")
        with patch.object(h, "fetch_product", return_value=product):
            self.assertIsNone(h.resolve_watchlist_equity("b" * 64), "mismatched IDs cannot be used")

    def test_unknown_equity_has_negative_cache_without_guessing(self):
        h = self.h
        with patch.object(h, "fetch_product", return_value={}) as get:
            for _ in range(2):
                self.assertEqual(h.parse_simple_watchlist({"items": [{"equityCbrn": "v1:equity:::" + "c" * 64 + ":"}]}), [])
        get.assert_called_once()

    def test_typed_read_items_map_to_correct_assets_in_api_order(self):
        rows = self.h.parse_simple_watchlist({"items": [{"equityCbrn": "v1:equity:::stock-coin:"}, {"assetUuid": "asset-btc"}]})
        self.assertEqual([r["id"] for r in rows], ["COIN", "BTC"])
        self.assertEqual(rows[0]["productId"], "stock-coin")
        self.assertEqual(rows[1]["productId"], "BTC-USD")
        self.assertEqual(rows[0]["watchlistItem"], {"equityCbrn": "v1:equity:::stock-coin:"})

    def test_xrp_add_roundtrip_recognizes_token_identity_and_removes_exact_reference(self):
        h = self.h
        uuid = "e17a44c8-6ea1-564f-a02c-2a9ca1d8eec4"
        h.crypto_asset_catalog = lambda: [{"assetUuid": uuid, "id": "XRP", "name": "XRP"}]
        row = {"kind": "crypto", "id": "XRP", "productId": "XRP-USD"}
        item = {"tokenCbrn": "v1:token:base:mainnet:0xcb585250f852C6c6bf90434AB21A00f02833a4af:"}
        self.assertEqual(h.watchlist_reference(row), {"assetUuid": uuid})
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "api_get", return_value={"items": [item]}), patch("sys.stdin", io.StringIO(json.dumps({"item": {"assetUuid": uuid}}))), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("add")
        self.assertTrue(json.loads(out.getvalue())["ok"])
        self.assertEqual(post.call_args.kwargs["body"], {"item": {"assetUuid": uuid}})
        entries = h.load_watchlist_state()["simpleEntries"]
        self.assertEqual([entry["id"] for entry in entries], ["XRP"])
        self.assertEqual(h.watchlist_status()["unsupported"], 0)
        state = h.watchlist_action_state(row)
        self.assertTrue(state["watched"])
        self.assertEqual(state["item"], item)
        with patch.object(h, "http_json", return_value={}) as post:
            h.mutate_simple_watchlist("synthetic", "remove", state["item"])
        self.assertEqual(post.call_args.kwargs["body"], {"item": item})

    def test_token_mapping_requires_exact_network_and_contract_identity(self):
        h = self.h
        cbrn = "v1:token:base:mainnet:0xcb585250f852C6c6bf90434AB21A00f02833a4af:"
        self.assertTrue(h.retail_token_asset_uuid(cbrn))
        for unknown in (cbrn.replace(":base:", ":ethereum:"), cbrn.replace(":mainnet:", ":testnet:"), cbrn.replace("a4af:", "a4aa:")):
            self.assertEqual(h.retail_token_asset_uuid(unknown), "")

    def test_zcash_token_roundtrip_uses_canonical_remove_identity(self):
        h = self.h
        uuid = "1d3c2625-a8d9-5458-84d0-437d75540421"
        h.crypto_asset_catalog = lambda: [{"assetUuid": uuid, "id": "ZEC", "name": "Zcash"}]
        item = {"tokenCbrn": "v1:token:base:mainnet:0xB2000000000000000000008501b13360000cb2EC:"}
        with patch.object(h, "api_get", return_value={"items": [item]}):
            entries = h.fetch_simple_watchlist("synthetic", force=True)
        self.assertEqual(entries[0]["id"], "ZEC")
        state = h.watchlist_action_state({"kind": "crypto", "id": "ZEC", "productId": "ZEC-USD"})
        self.assertTrue(state["watched"])
        self.assertEqual(state["item"], item)
        with patch.object(h, "http_json", return_value={}) as post:
            h.mutate_simple_watchlist("synthetic", "remove", state["item"])
        self.assertEqual(post.call_args.kwargs["body"], {"item": item})

    def test_watchlist_click_waits_for_writer_instead_of_skipping_like_background_jobs(self):
        h = self.h
        with patch("sys.argv", ["coinbase", "watchlist-action", "add"]), patch.object(h, "dispatch"):
            h.main()
        self.assertFalse(h._BACKGROUND_JOB)
        with patch("sys.argv", ["coinbase", "watchlist-refresh"]), patch.object(h, "dispatch"):
            h.main()
        self.assertTrue(h._BACKGROUND_JOB)

    def test_unexpected_envelope_is_not_empty_watchlist(self):
        for payload in (None, [], {"items": {}}, {"items": [None]}, {"items": [{"assetUuid": "a", "tokenCbrn": "b"}]}):
            with self.assertRaises(RuntimeError):
                self.h.parse_simple_watchlist(payload)

    def test_refresh_uses_simple_endpoint_and_ignores_advanced_cache(self):
        h = self.h
        h.save_watchlist_state(advanced=[{"id": "OLD"}], advancedAt=9999999999)
        with patch.object(h, "api_get", return_value={"items": [{"assetUuid": "asset-btc"}]}) as get, patch.object(h, "fetch_advanced_watchlist", side_effect=AssertionError("legacy API called")):
            rows = h.merge_watchlist([], "synthetic")
        get.assert_called_once_with("/v2/watchlist/items", "synthetic")
        self.assertEqual([r["id"] for r in rows], ["BTC"])
        self.assertEqual(h.watchlist_status()["source"], "simple")

    def test_failed_read_keeps_only_previous_simple_cache(self):
        h = self.h
        h.save_watchlist_state(advanced=[{"id": "OLD"}])
        with patch.object(h, "api_get", side_effect=RuntimeError("offline")):
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [])
            h.save_watchlist_state(simpleEntries=[{"id": "BTC"}], simpleAt=1)
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [{"id": "BTC"}])
        self.assertTrue(h.watchlist_status()["error"])

    def test_missing_read_scope_never_uses_advanced_or_sends_request(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:update"}
        with patch.object(h, "api_get") as get:
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [])
        get.assert_not_called()
        self.assertFalse(h.watchlist_status()["ready"])

    def test_unknown_item_is_reported_not_mapped_to_crypto(self):
        h = self.h
        with patch.object(h, "api_get", return_value={"items": [{"predictionCbrn": "v1:prediction:test"}]}):
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [])
        self.assertEqual(h.watchlist_status()["unsupported"], 1)
        self.assertTrue(h.watchlist_status()["ready"])

    def test_omitted_items_is_documented_empty_list(self):
        self.assertEqual(self.h.parse_simple_watchlist({}), [])
        with patch.object(self.h, "api_get", return_value={}):
            self.assertEqual(self.h.fetch_simple_watchlist("synthetic"), [])
        self.assertTrue(self.h.watchlist_status()["ready"])

    def test_add_and_remove_use_documented_post_bodies(self):
        h = self.h
        asset = {"assetUuid": "11111111-1111-1111-1111-111111111111"}
        token = {"tokenCbrn": "v1:token:base:mainnet:0xtest:"}
        with patch.object(h, "http_json", return_value={}) as request, patch.object(h, "api_get") as read:
            h.mutate_simple_watchlist("synthetic", "add", asset)
            h.mutate_simple_watchlist("synthetic", "remove", token)
        self.assertEqual(request.call_args_list[0].args, ("POST", h.API + "/v2/watchlist/items"))
        self.assertEqual(request.call_args_list[0].kwargs["body"], {"item": asset})
        self.assertEqual(request.call_args_list[1].args, ("POST", h.API + "/v2/watchlist/items/remove"))
        self.assertEqual(request.call_args_list[1].kwargs["body"], {"item": token})
        read.assert_not_called()

    def test_read_only_grant_cannot_mutate(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:read"}
        with patch.object(h, "http_json") as request, self.assertRaises(RuntimeError):
            h.mutate_simple_watchlist("synthetic", "remove", {"tokenCbrn": "v1:token:test"})
        request.assert_not_called()

    def test_update_only_grant_can_mutate_without_reading(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:update"}
        with patch.object(h, "http_json", return_value={}) as request, patch.object(h, "api_get") as read:
            h.mutate_simple_watchlist("synthetic", "remove", {"equityCbrn": "v1:equity:::delisted:"})
        request.assert_called_once()
        read.assert_not_called()

    def test_rejects_invalid_identifiers_before_request(self):
        h = self.h
        for item in ({}, {"assetUuid": "bad"}, {"assetUuid": "a", "tokenCbrn": "b"}, {"unknown": "a"}, {"deribitPerpetualInstrumentId": "abc"}, None):
            with patch.object(h, "http_json") as request, self.assertRaises(RuntimeError):
                h.mutate_simple_watchlist("synthetic", "add", item)
            request.assert_not_called()

    def test_removal_uses_stored_identity_without_asset_resolution(self):
        h = self.h
        item = {"tokenCbrn": "v1:token:base:mainnet:0xtest:"}
        h.save_watchlist_state(simpleItems=[item], simpleEntries=[])
        with patch.object(h, "crypto_asset_catalog", side_effect=AssertionError("must not re-resolve removal")):
            state = h.watchlist_action_state({"kind": "crypto", "id": "BTC", "watchlistItem": item})
        self.assertEqual(state["item"], item)
        self.assertTrue(state["watched"])

    def test_acknowledged_write_is_not_failed_when_followup_read_fails(self):
        h = self.h
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as request, patch.object(h, "api_get", side_effect=RuntimeError("offline")), patch("sys.stdin", io.StringIO(json.dumps({"item": {"tokenCbrn": "v1:token:test"}}))), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("remove")
        self.assertTrue(json.loads(out.getvalue())["ok"])
        self.assertIn("Refresh pending", json.loads(out.getvalue())["message"])
        request.assert_called_once()

    def test_unsupported_items_are_skipped_without_modifying_server_list(self):
        h = self.h
        item = {"predictionCbrn": "v1:prediction:test"}
        with patch.object(h, "api_get", return_value={"items": [item]}) as get, patch.object(h, "http_json") as post:
            rows = h.merge_watchlist_entries([], h.fetch_simple_watchlist("synthetic"))
        self.assertEqual(rows, [])
        self.assertEqual(h.watchlist_status()["items"], [item])
        get.assert_called_once()
        post.assert_not_called()

    def test_update_only_command_does_not_attempt_read_after_write(self):
        h = self.h
        h.granted_scopes = lambda: {"wallet:watchlist:update"}
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}) as post, patch.object(h, "api_get") as get, patch("sys.stdin", io.StringIO('{"item":{"futureProductId":"TEST-CDE"}}')), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("add")
        post.assert_called_once()
        get.assert_not_called()
        self.assertTrue(json.loads(out.getvalue())["ok"])

    def test_successful_mutations_need_no_inline_confirmation(self):
        h = self.h
        for action in ("add", "remove"):
            with self.subTest(action=action):
                out = io.StringIO()
                with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", return_value={}), patch.object(h, "api_get", return_value={}), patch("sys.stdin", io.StringIO('{"item":{"equityProductId":"stock-coin"}}')), contextlib.redirect_stdout(out):
                    h.cmd_watchlist_action(action)
                result = json.loads(out.getvalue())
                self.assertTrue(result["ok"])
                self.assertEqual(result["message"], "")

    def test_failed_write_does_not_publish_success_or_change_cached_membership(self):
        h = self.h
        h.save_watchlist_state(simpleItems=[{"tokenCbrn": "v1:token:test"}])
        out = io.StringIO()
        with patch.object(h, "valid_access_token", return_value="synthetic"), patch.object(h, "http_json", side_effect=RuntimeError("HTTP 500 hidden body")), patch.object(h, "api_get") as get, patch("sys.stdin", io.StringIO('{"item":{"tokenCbrn":"v1:token:test"}}')), contextlib.redirect_stdout(out):
            h.cmd_watchlist_action("remove")
        get.assert_not_called()
        result = json.loads(out.getvalue())
        self.assertFalse(result["ok"])
        self.assertNotIn("hidden body", result["message"])
        self.assertEqual(h.load_watchlist_state()["simpleItems"], [{"tokenCbrn": "v1:token:test"}])

    def test_logout_race_does_not_repopulate_watchlist_cache(self):
        h = self.h
        h.token_is_current = lambda token: False
        with patch.object(h, "api_get", return_value={"items": [{"assetUuid": "asset-btc"}]}):
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [])
        self.assertFalse(h.WATCHLIST_FILE.exists())

    def test_real_empty_list_clears_old_simple_entries(self):
        h = self.h
        h.save_watchlist_state(simpleEntries=[{"id": "BTC"}], simpleAt=1)
        with patch.object(h, "api_get", return_value={"items": []}):
            self.assertEqual(h.fetch_simple_watchlist("synthetic"), [])
        self.assertEqual(h.watchlist_status()["items"], [])
        self.assertTrue(h.watchlist_status()["ready"])
