import QtQuick
import Quickshell.Io

// Safety ceiling for silent background network work.
// Background snapshot jobs skip lock contention instead of waiting in a queue.
// SIGKILL also releases file locks if a helper ignores graceful termination.
Process {
  id: root
  property int deadlineMs: 120000
  property Timer watchdog: Timer {
    interval: root.deadlineMs
    running: root.running
    onTriggered: root.signal(9)
  }
}
