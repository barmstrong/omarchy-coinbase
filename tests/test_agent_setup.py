import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load_setup():
    path = Path(__file__).resolve().parents[1] / 'bin/setup-agents'
    loader = importlib.machinery.SourceFileLoader('agent_setup', str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class AgentSetupTests(unittest.TestCase):
    def setUp(self):
        self.h = load_setup()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.state = self.home / 'state'
        self.state.mkdir()
        self.data = self.home / 'data'
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.calls = []

    def fake_run(self, args, **kwargs):
        self.calls.append(args)
        if 'ci' in args:
            release = Path(args[args.index('--prefix') + 1])
            package = release / 'node_modules/@coinbase/coinbase-cli'
            (package / 'dist').mkdir(parents=True, exist_ok=True)
            (package / 'dist/index.js').write_text('test')
            (package / 'package.json').write_text(json.dumps({'name': '@coinbase/coinbase-cli', 'version': '0.0.10'}))
        return '0.0.10'

    def install(self):
        with patch.object(self.h, 'node_runtime', return_value=(Path('/test/node'), '/test/npm')), \
             patch.object(self.h, 'run', side_effect=self.fake_run), \
             patch.object(self.h.shutil, 'which', return_value=None):
            return self.h.setup(self.home, self.state, self.data)

    def test_install_is_pinned_repeatable_and_repairs_deleted_links(self):
        self.install()
        wrapper = self.home / '.local/bin/coinbase'
        self.assertTrue(os.access(wrapper, os.X_OK))
        self.assertIn('/test/node', wrapper.read_text())
        self.assertTrue((self.home / '.agents/skills/coinbase-cli').is_symlink())
        first_calls = len(self.calls)
        self.install()
        self.assertEqual(len(self.calls), first_calls, 'healthy repeat setup has no network work')
        link = self.home / '.claude/skills/coinbase-cli'
        link.unlink()
        profile = self.home / '.hermes/profiles/new-agent'
        profile.mkdir(parents=True)
        self.install()
        self.assertTrue(link.is_symlink())
        self.assertTrue((profile / 'skills/coinbase-cli').is_symlink())
        install_command = next(c for c in self.calls if 'ci' in c)
        self.assertIn('--ignore-scripts', install_command)

    def test_existing_command_is_not_overwritten(self):
        command = self.home / '.local/bin/coinbase'
        command.parent.mkdir(parents=True)
        command.write_text('user command')
        with self.assertRaisesRegex(RuntimeError, 'Preserved existing'):
            self.install()
        self.assertEqual(command.read_text(), 'user command')
        self.assertEqual(self.calls, [])

    def test_existing_skill_is_preserved_and_cleanup_only_removes_ours(self):
        custom = self.home / '.claude/skills/coinbase-cli'
        custom.mkdir(parents=True)
        (custom / 'SKILL.md').write_text('user instructions')
        result = self.install()
        self.assertTrue(any('preserved existing' in s for s in result['skills']))
        self.h.remove(self.home, self.state, self.data)
        self.assertEqual((custom / 'SKILL.md').read_text(), 'user instructions')
        self.assertFalse(os.path.lexists(self.home / '.agents/skills/coinbase-cli'))
        self.assertFalse((self.home / '.local/bin/coinbase').exists())
        calls = len(self.calls)
        self.assertEqual(self.install(), {'disabled': True})
        self.assertEqual(len(self.calls), calls)

    def test_replaced_wrapper_is_preserved_on_removal(self):
        self.install()
        wrapper = self.home / '.local/bin/coinbase'
        wrapper.write_text('replacement command')
        self.h.remove(self.home, self.state, self.data)
        self.assertEqual(wrapper.read_text(), 'replacement command')

    def test_removal_purges_only_owned_runtime_and_preserves_credentials(self):
        self.install()
        owned = next(self.data.glob('runtime-*'))
        independent = self.data / 'runtime-unmanaged'
        independent.mkdir()
        credentials = self.home / '.config/coinbase/credentials'
        credentials.parent.mkdir(parents=True)
        credentials.write_text('test credential')
        external = self.home / 'external-runtime'
        external.mkdir()
        (external / self.h.RUNTIME_MARKER).write_text(self.h.MARKER + '\n')
        (self.data / 'runtime-external').symlink_to(external, target_is_directory=True)
        self.h.remove(self.home, self.state, self.data)
        self.assertFalse(owned.exists())
        self.assertTrue(independent.exists())
        self.assertTrue(external.exists())
        self.assertEqual(credentials.read_text(), 'test credential')

    def installed_plugin(self):
        target = self.home / '.config/omarchy/plugins/coinbase'
        target.mkdir(parents=True)
        shutil.copytree(self.h.ROOT / 'cli', target / 'cli')
        shutil.copytree(self.h.SKILL, target / 'skills/coinbase-cli')
        root = patch.object(self.h, 'ROOT', target)
        skill = patch.object(self.h, 'SKILL', target / 'skills/coinbase-cli')
        root.start()
        skill.start()
        self.addCleanup(root.stop)
        self.addCleanup(skill.stop)
        self.install()
        return target

    def test_canceled_uninstall_preserves_integration(self):
        self.installed_plugin()
        with patch.object(self.h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(RuntimeError, 'left intact'):
                self.h.uninstall(self.home, self.state, self.data)
        self.assertTrue((self.home / '.local/bin/coinbase').exists())
        self.assertTrue((self.home / '.agents/skills/coinbase-cli').is_symlink())
        self.assertTrue(next(self.data.glob('runtime-*')).exists())
        self.assertFalse((self.state / 'disabled').exists())

    def test_uninstall_cleans_after_native_removal_and_allows_reinstall(self):
        target = self.installed_plugin()

        def native_remove(command, **kwargs):
            self.assertEqual(command, ['omarchy', 'plugin', 'remove', 'coinbase', '--yes'])
            shutil.rmtree(target)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(self.h.subprocess, 'run', side_effect=native_remove):
            result = self.h.uninstall(self.home, self.state, self.data, assume_yes=True)
        self.assertTrue(result['uninstalled'])
        self.assertFalse((self.home / '.local/bin/coinbase').exists())
        self.assertFalse(os.path.lexists(self.home / '.agents/skills/coinbase-cli'))
        self.assertEqual(list(self.data.glob('runtime-*')), [])
        self.assertFalse((self.state / 'disabled').exists())

    def test_uninstall_from_uninstalled_checkout_is_refused(self):
        with patch.object(self.h.subprocess, 'run') as native:
            with self.assertRaisesRegex(RuntimeError, 'Run uninstall using'):
                self.h.uninstall(self.home, self.state, self.data)
            native.assert_not_called()

    def test_failed_package_install_is_retried_without_ready_marker(self):
        with patch.object(self.h, 'node_runtime', return_value=(Path('/test/node'), '/test/npm')), \
             patch.object(self.h, 'run', side_effect=RuntimeError('offline')), \
             patch.object(self.h.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'offline'):
                self.h.setup(self.home, self.state, self.data)
        self.assertFalse((self.home / '.local/bin/coinbase').exists())
        self.install()
        self.assertTrue((self.home / '.local/bin/coinbase').exists())


if __name__ == '__main__':
    unittest.main()
