import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: test
  property int step: 0
  property int refreshes: 0
  property bool forced: false
  Plugin.RecoveryTimer {
    id: recovery
    running: false
    onRefreshRequested: function(force) {
      test.refreshes += 1
      test.forced = force
    }
  }
  Component.onCompleted: {
    recovery.snapshot = {fetchedAt: new Date().toISOString()}
    recovery.triggered()
    if (test.refreshes !== 0) throw new Error("fresh data caused a recovery request")
    recovery.lastTick = Date.now() - 60000
    recovery.triggered()
    if (test.refreshes !== 1 || !test.forced) throw new Error("wake did not force recovery")
    recovery.snapshot = {fetchedAt: "2026-01-01T00:00:00Z"}
    recovery.triggered()
    if (test.refreshes !== 2 || test.forced) throw new Error("stale retry must honor cooldown")
    recovery.snapshot = {fetchedAt: new Date().toISOString(), error: "offline"}
    recovery.triggered()
    if (test.refreshes !== 3 || test.forced) throw new Error("failed refresh did not retry")
  }
  Plugin.RefreshProcess {
    id: helper
    deadlineMs: 150
    onStarted: {
      if (test.step === 4) Qt.callLater(function() { helper.startedAt = Date.now() - 180000 })
    }
  }
  Timer {
    interval: 1200
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
      else if (test.step === 3) {
        helper.deadlineMs = 120000
        helper.command = ["/usr/bin/sleep", "30"]
      }
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
