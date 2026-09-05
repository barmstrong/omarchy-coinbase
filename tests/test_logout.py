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
    def test_logout_clears_private_snapshot_before_network_work(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            helper.STATE_DIR = state
            helper.APP_FILE = state / "oauth-app.json"
            helper.TOKEN_FILE = state / "tokens.json"
            helper.SNAPSHOT_FILE = state / "snapshot.json"
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
                self.assertEqual(snapshot["assets"], [])
                self.assertEqual(snapshot["user"], {})
                self.assertEqual(snapshot["period"], "week")
                self.assertEqual(snapshot["bar"]["period"], "week")
                status = json.loads(helper.LOGIN_STATUS_FILE.read_text(encoding="utf-8"))
                self.assertEqual(status["status"], "logged-out")
                raise RuntimeError("simulated offline revoke")

            market_refreshed = False

            def fake_build_market_snapshot(period):
                nonlocal market_refreshed
                market_refreshed = True
                self.assertEqual(period, "week")

            helper.http_json = fake_http_json
            helper.build_market_snapshot = fake_build_market_snapshot
            with contextlib.redirect_stdout(io.StringIO()):
                helper.cmd_logout()

            self.assertTrue(revoke_checked)
            self.assertTrue(market_refreshed)
            self.assertFalse(helper.token_is_current("private-token"))


if __name__ == "__main__":
    unittest.main()
