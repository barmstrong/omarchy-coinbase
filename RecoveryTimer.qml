import QtQuick
import "Model.js" as Model

// Wall time advances across suspend, unlike the regular refresh timer.
Timer {
  id: root
  property var snapshot: ({})
  property double lastTick: Date.now()
  property double now: Date.now()
  signal refreshRequested(bool force)
  interval: 5000
  repeat: true
  running: true
  onTriggered: {
    now = Date.now()
    var resumed = now - lastTick > 15000
    lastTick = now
    if (resumed || snapshot.error || Model.snapshotNeedsRefresh(snapshot, now))
      refreshRequested(resumed)
  }
}
