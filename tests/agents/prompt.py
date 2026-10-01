#!/usr/bin/env python3
"""Exercise real gum prompts in a PTY; package installation is stubbed."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import sys
import tempfile
import termios
import time

path = str(Path(__file__).resolve().parents[2] / 'bin/setup-agents')
loader = importlib.machinery.SourceFileLoader('setup', path)
spec = importlib.util.spec_from_loader(loader.name, loader)
setup = importlib.util.module_from_spec(spec)
loader.exec_module(setup)

for case, inputs in [('cli-only', [b'\r', b'\r']), ('codex-only', [b'\r', b'\x1b[Bx\r']), ('decline', [b'\x1b[C\r']), ('cancel', [b'\x03'])]:
    with tempfile.TemporaryDirectory(prefix='coinbase-optin-') as directory:
        home = Path(directory)
        state = home / 'state'
        state.mkdir()
        sys.stdout.flush()
        pid, terminal = pty.fork()
        if pid == 0:
            try:
                for key in ['XDG_CONFIG_HOME', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'HERMES_HOME', 'GROK_HOME']:
                    os.environ.pop(key, None)
                os.environ['TERM'] = 'xterm-256color'
                termios.tcsetwinsize(0, (35, 120))
                setup.ensure_cli = lambda *_: {'version': 'test-only'}
                result = setup.configure(home, state, home / 'data')
                (home / 'result.json').write_text(json.dumps(result))
                os._exit(0)
            except BaseException as exc:
                (home / 'error.txt').write_text(repr(exc))
                os._exit(1)
        output = b''
        stage = 0
        deadline = time.monotonic() + 12
        try:
            while time.monotonic() < deadline:
                if select.select([terminal], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(terminal, 65536)
                    except OSError:
                        break
                    output += chunk
                    if b'\x1b[6n' in chunk:
                        os.write(terminal, b'\x1b[1;1R')
                trigger = b'Install Coinbase CLI?' if stage == 0 else b'Share the Coinbase skill with:'
                if stage < len(inputs) and trigger in output:
                    time.sleep(0.25)
                    for key in ([b'\x1b[B', b'x', b'\r'] if case == 'codex-only' and stage == 1 else [inputs[stage]]):
                        os.write(terminal, key)
                        time.sleep(0.15)
                    stage += 1
                if (home / 'result.json').exists() or (home / 'error.txt').exists():
                    break
            assert (home / 'result.json').exists(), (case, output.decode(errors='replace')[-1800:])
            chosen = setup.selection(state)
            if case == 'cli-only':
                assert chosen['cli'] and chosen['directories'] == [], chosen
            elif case == 'codex-only':
                assert chosen['directories'] == [str(home / '.codex/skills')], (chosen, output.decode(errors='replace')[-2000:])
            elif case == 'decline':
                assert chosen['cli'] is False, chosen
            else:
                assert chosen is None, chosen
            print('PASS real terminal prompt:', case)
        finally:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
            os.close(terminal)
