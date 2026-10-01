import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false

  Process {
    id: setup
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("bin/setup-agents").toString().replace(/^file:\/\//, "")), "ensure"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0)
        console.warn("Coinbase CLI setup needs attention; run the plugin's bin/setup-agents status for details.")
    }
  }

  // Runs on enable and shell startup. Reconcile missing agent/profile links
  // without repeated downloads once the pinned runtime is installed.
  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!setup.running) setup.running = true
  }
}
