#!/usr/bin/env python3
"""Exercise the real QML setup service with an isolated, harmless installer."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='coinbase service test ') as directory:
    stage = Path(directory)
    shutil.copyfile(root / 'AgentSetup.qml', stage / 'AgentSetup.qml')
    (stage / 'bin').mkdir()
    (stage / 'bin/setup-agents').write_text('''from pathlib import Path
import sys
assert sys.argv[1:] == ["onboard"]
(Path(__file__).resolve().parents[1] / "invoked").write_text("ok")
''')
    (stage / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
  AgentSetup {}
  Timer { interval: 1000; running: true; onTriggered: Qt.quit() }
}
''')
    runtime = stage / 'runtime'
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
               QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
    env.pop('DISPLAY', None)
    result = subprocess.run(['quickshell', '-p', str(stage / 'shell.qml'), '--no-color'],
                            env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (stage / 'invoked').read_text() == 'ok', result.stdout + result.stderr
    print('PASS: service offers onboarding; paths containing spaces work')
