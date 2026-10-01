import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false
  readonly property string setupPath: decodeURIComponent(Qt.resolvedUrl("bin/setup-agents").toString().replace(/^file:\/\//, ""))
  Component.onCompleted: {
    setup.command = ["python3", root.setupPath, "onboard"]
    setup.running = true
  }

  Process {
    id: setup
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0)
        console.warn("Coinbase CLI setup needs attention; run the plugin's bin/setup-agents status for details.")
    }
  }

  // Background work only reconciles the user's explicitly saved selection.
  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: {
      if (!setup.running) {
        setup.command = ["python3", root.setupPath, "ensure"]
        setup.running = true
      }
    }
  }
}
