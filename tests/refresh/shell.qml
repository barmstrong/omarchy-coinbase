import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  Plugin.RefreshProcess {
    id: helper
    deadlineMs: 150
  }
  Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: {
      if (helper.running) {
        console.error("FAIL: helper remained busy at step " + test.step)
        Qt.quit()
        return
      }
      if (test.step === 0) helper.command = ["/usr/bin/sleep", "30"]
      else if (test.step === 1) helper.command = ["/usr/bin/true"]
      else if (test.step === 2) helper.command = ["/nonexistent/coinbase-refresh-test"]
      else {
        console.log("PASS: stalled helper terminated, retry completed, failed start cleared")
        Qt.quit()
        return
      }
      test.step += 1
      helper.running = true
    }
  }
}
