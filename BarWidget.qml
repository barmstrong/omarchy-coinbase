import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "coinbase"

  property var snapshot: ({})
  property bool refreshing: false
  property string lastSnapshotRaw: ""
  property string loginPhase: ""

  readonly property int refreshSeconds: Math.max(15, parseInt(setting("refreshSeconds", 60), 10) || 60)
  readonly property bool signedIn: snapshot.authenticated === true
  readonly property bool authLoading: root.loginPhase === "exchanging"
    || root.loginPhase === "snapshot"
    || (root.signedIn && snapshot.loading === true)
  readonly property var barPnl: snapshot.bar || ({})
  readonly property string tickerText: String(barPnl.symbol || "BTC").toUpperCase()
  readonly property real quotePrice: Number(signedIn ? snapshot.total : barPnl.price)
  readonly property real pnl: Number(barPnl.pnl)
  readonly property real pnlPercent: Number(barPnl.pnlPercent)
  readonly property bool hasQuote: isFinite(quotePrice) && quotePrice > 0
  readonly property color pnlColor: Model.pnlColor(pnlPercent, Color.accent, Color.urgent, bar ? bar.barForeground : Color.foreground)
  readonly property string totalText: Model.formatCompactUsd(quotePrice)
  readonly property string pnlText: Model.formatPercent(pnlPercent)
  readonly property string barDisplay: {
    var mode = String(snapshot.barDisplay || "full")
    if (mode === "quote" || mode === "price") return mode
    return "full"
  }
  readonly property bool showTicker: !signedIn && !authLoading && barDisplay !== "price"
  readonly property bool showPrice: hasQuote && (!authLoading || signedIn) && (!signedIn || barDisplay !== "price")
  readonly property bool showPnl: !authLoading && hasQuote && barDisplay === "full" && isFinite(pnlPercent)
  readonly property string chipText: authLoading
    ? (signedIn && hasQuote && barDisplay !== "price" ? totalText : "CB")
    : (signedIn
      ? (hasQuote ? (barDisplay === "full" ? (totalText + "  " + pnlText) : (barDisplay === "quote" ? totalText : "CB")) : "CB")
      : (hasQuote ? (barDisplay === "price" ? totalText : (barDisplay === "quote" ? (tickerText + "  " + totalText) : (tickerText + "  " + totalText + "  " + pnlText))) : tickerText))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function pluginFile(rel) {
    var url = String(Qt.resolvedUrl(rel))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url
  }

  function applySnapshot(raw) {
    var serialized = String(raw || "")
    if (serialized !== "" && serialized === root.lastSnapshotRaw) return
    var next = Model.parseSnapshot(serialized, null)
    if (next) {
      root.lastSnapshotRaw = serialized
      snapshot = next
    }
  }

  function refresh(force) {
    if (snapshotProc.running) return
    refreshing = true
    snapshotProc.command = [root.pluginFile("bin/coinbase"), "snapshot"]
    if (!force) snapshotProc.command.push("--max-age", "20")
    snapshotProc.running = true
  }

  function togglePanel() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle("coinbase", "{}")
  }

  function logout() {
    if (!signedIn || logoutProc.running) return
    if (snapshotProc.running) snapshotProc.running = false
    logoutProc.running = true
  }

  function cycleDisplay() {
    if (displayProc.running) displayProc.running = false
    displayProc.running = true
  }

  FileView {
    id: snapshotFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/coinbase/snapshot.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySnapshot(text())
  }

  FileView {
    id: loginStatusFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/coinbase/login-status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var data = {}
      try { data = JSON.parse(text() || "{}") } catch (e) { data = {} }
      var status = String(data.status || "")
      var changedAt = Date.parse(String(data.at || ""))
      var recent = isFinite(changedAt) && Date.now() - changedAt < 5 * 60 * 1000
      root.loginPhase = recent && (status === "exchanging" || status === "snapshot") ? status : ""
    }
  }

  Process {
    id: snapshotProc
    command: [root.pluginFile("bin/coinbase"), "snapshot"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.refreshing = false
      snapshotFile.reload()
    }
  }

  Process {
    id: logoutProc
    command: [root.pluginFile("bin/coinbase"), "logout"]
    onExited: snapshotFile.reload()
  }

  Process {
    id: displayProc
    command: [root.pluginFile("bin/coinbase"), "display"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw.indexOf("{") === -1) return
        try {
          var data = JSON.parse(raw)
          var next = Object.assign({}, root.snapshot)
          next.barDisplay = data.barDisplay
          root.snapshot = next
        } catch (e) {}
      }
    }
    onExited: snapshotFile.reload()
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 25000
    running: snapshotProc.running
    onTriggered: snapshotProc.running = false
  }

  Timer {
    interval: 1500
    running: true
    onTriggered: snapshotFile.reload()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.chipText
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh(true)
      else if (b === Qt.RightButton) root.cycleDisplay()
      else root.togglePanel()
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(8)

      CoinbaseIcon {
        visible: root.signedIn || root.authLoading
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.bar.iconCanvas
        color: button.foreground
        opacity: 1
      }

      Text {
        visible: root.authLoading
        anchors.verticalCenter: parent.verticalCenter
        text: "󰦖"
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize

        RotationAnimator on rotation {
          running: root.authLoading
          from: 0
          to: 360
          duration: 800
          loops: Animation.Infinite
        }
      }

      Text {
        visible: root.showTicker
        anchors.verticalCenter: parent.verticalCenter
        text: root.tickerText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
      }

      Text {
        visible: root.showPrice && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: root.totalText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        visible: root.showPnl && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: root.pnlText
        color: root.pnlColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }
}
