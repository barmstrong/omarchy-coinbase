import contextlib
import fcntl
import io
import subprocess
import tempfile
import unittest
import urllib.parse
from pathlib import Path
from unittest.mock import patch

from test_reliability import configure_state, load_helper


class LoginFlowTests(unittest.TestCase):
    def setUp(self):
        self.h = load_helper()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        configure_state(self.h, Path(self.temp.name))

    def test_all_accounts_preserves_security_parameters(self):
        params = {'state': 'test-state', 'code_challenge': 'test-pkce',
                  'code_challenge_method': 'S256', 'scope': self.h.SCOPES,
                  'redirect_uri': 'https://broker.example/oauth/callback', 'account': 'select'}
        url = self.h.AUTH_URL + '?' + urllib.parse.urlencode(params)
        result = self.h.all_accounts_authorize_url(url)
        self.assertEqual(dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(result).query)),
                         dict(params, account='all'))
        self.assertEqual(self.h.all_accounts_authorize_url(result), result)

    def test_invalid_authorization_urls_are_rejected(self):
        for url in ['http://login.coinbase.com/oauth2/auth', 'https://attacker.example/oauth2/auth',
                    'https://login.coinbase.com@attacker.example/oauth2/auth',
                    'https://login.coinbase.com/another-path']:
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                self.h.all_accounts_authorize_url(url)

    def test_existing_broker_also_gets_all_accounts_without_redeployment(self):
        authorize = self.h.AUTH_URL + '?state=test-state&code_challenge=test-pkce'
        responses = [{'authorize_url': authorize, 'session_id': 'test-session'},
                     {'access_token': 'test-token'}]
        with patch.object(self.h, 'broker_url', return_value='https://broker.example'), \
             patch.object(self.h, 'http_json', side_effect=responses), \
             patch.object(self.h, 'open_browser') as launch, \
             patch.object(self.h.time, 'sleep'), \
             patch.object(self.h, '_finish_login'), contextlib.redirect_stdout(io.StringIO()):
            self.h.login_via_broker()
        launch.assert_called_once()
        self.assertEqual(dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(launch.call_args.args[0]).query)),
                         {'state': 'test-state', 'code_challenge': 'test-pkce', 'account': 'all'})

    def test_desktop_opener_launches_once_without_forcing_a_window(self):
        with patch.object(self.h.shutil, 'which', return_value='/usr/bin/gio'), \
             patch.object(self.h.subprocess, 'run') as launch:
            self.h.open_browser('https://www.coinbase.com')
        launch.assert_called_once()
        self.assertEqual(launch.call_args.args[0], ['gio', 'open', 'https://www.coinbase.com'])

    def test_xdg_fallback_is_used_only_when_gio_is_missing(self):
        with patch.object(self.h.shutil, 'which', return_value=None), \
             patch.object(self.h.subprocess, 'run') as launch:
            self.h.open_browser('https://www.coinbase.com')
        self.assertEqual(launch.call_args.args[0], ['xdg-open', 'https://www.coinbase.com'])

    def test_launch_failure_does_not_retry_another_browser(self):
        with patch.object(self.h.shutil, 'which', return_value='/usr/bin/gio'), \
             patch.object(self.h.subprocess, 'run', side_effect=subprocess.TimeoutExpired('gio', 15)) as launch:
            with self.assertRaises(subprocess.TimeoutExpired):
                self.h.open_browser('https://www.coinbase.com')
        launch.assert_called_once()

    def test_disallowed_browser_urls_never_launch(self):
        with patch.object(self.h.subprocess, 'run') as launch:
            for url in ['https://attacker.example', 'file:///tmp/test', 'https://u:p@coinbase.com']:
                with self.assertRaises(RuntimeError):
                    self.h.open_browser(url)
        launch.assert_not_called()

    def test_concurrent_login_does_not_open_or_queue_a_second_flow(self):
        self.h.write_login_status('waiting')
        original = self.h.LOGIN_STATUS_FILE.read_text()
        with (self.h.STATE_DIR / 'login.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with patch.object(self.h, '_perform_login') as login, contextlib.redirect_stdout(io.StringIO()):
                self.h.cmd_login()
            login.assert_not_called()
        self.assertEqual(self.h.LOGIN_STATUS_FILE.read_text(), original)
        with patch.object(self.h, '_perform_login') as login:
            self.h.cmd_login()
        login.assert_called_once()

    def test_failed_login_releases_lock_and_reports_failure(self):
        with patch.object(self.h, '_perform_login', side_effect=OSError('test failure')):
            with self.assertRaises(OSError):
                self.h.cmd_login()
        self.assertEqual(self.h.read_json(self.h.LOGIN_STATUS_FILE, {})['status'], 'error')
        with patch.object(self.h, '_perform_login') as retry:
            self.h.cmd_login()
        retry.assert_called_once()


if __name__ == '__main__':
    unittest.main()
