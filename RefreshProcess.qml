import QtQuick
import Quickshell.Io

// Safety ceiling for silent background network work.
// Background snapshot jobs skip lock contention instead of waiting in a queue.
// SIGKILL also releases file locks if a helper ignores graceful termination.
Process {
  id: root
  property int deadlineMs: 120000
  property double startedAt: 0
  onRunningChanged: if (running) startedAt = Date.now()
  // Check elapsed wall time on wake so a pre-suspend job cannot block a
  // fresh attempt for another full timeout after the network returns.
  property Timer resumeWatchdog: Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: {
      if (Date.now() - root.startedAt >= root.deadlineMs) root.signal(9)
    }
  }
  property Timer watchdog: Timer {
    interval: root.deadlineMs
    running: root.running
    onTriggered: root.signal(9)
  }
}
