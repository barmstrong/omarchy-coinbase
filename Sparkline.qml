import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var values: []
  property color stroke: Color.accent
  property color fill: Util.alpha(stroke, 0.12)
  property color foreground: Color.foreground
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property bool compact: false
  property bool interactive: !compact
  property real axisWidth: compact ? 0 : Style.space(52)
  property real lineWidth: compact ? 1.35 : 1.75
  property bool hoverActive: false
  property int hoverIndex: -1

  readonly property real plotWidth: Math.max(1, width - axisWidth)
  readonly property var geo: Model.sparklineGeometry(values, plotWidth, Math.max(0, height))
  readonly property real hoverPrice: {
    if (!hoverActive || hoverIndex < 0 || !geo.values || hoverIndex >= geo.values.length) return NaN
    return Number(geo.values[hoverIndex])
  }

  signal hovered(bool active, real price, int index)

  onValuesChanged: paintSoon.restart()
  onWidthChanged: paintSoon.restart()
  onHeightChanged: paintSoon.restart()
  onStrokeChanged: paintSoon.restart()
  onHoverIndexChanged: paintSoon.restart()
  onHoverActiveChanged: paintSoon.restart()
  onVisibleChanged: if (visible) paintSoon.restart()
  Component.onCompleted: paintSoon.restart()

  function indexAt(x) {
    var pts = geo.points
    if (!pts || pts.length < 2) return -1
    var t = Math.max(0, Math.min(1, x / Math.max(1, plotWidth)))
    return Math.round(t * (pts.length - 1))
  }

  Timer {
    id: paintSoon
    interval: 16
    onTriggered: canvas.requestPaint()
  }

  Canvas {
    id: canvas
    width: root.plotWidth
    height: parent.height
    antialiasing: true
    renderStrategy: Canvas.Immediate
    onPaint: {
      var ctx = getContext("2d")
      if (!ctx) return
      ctx.reset()
      var pts = root.geo.points
      if (!pts || pts.length < 2 || width < 2 || height < 2) return

      ctx.globalAlpha = 0.42
      ctx.beginPath()
      ctx.moveTo(pts[0].x, height)
      for (var i = 0; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
      ctx.lineTo(pts[pts.length - 1].x, height)
      ctx.closePath()
      ctx.fillStyle = root.fill
      ctx.fill()

      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (var j = 1; j < pts.length; j++) ctx.lineTo(pts[j].x, pts[j].y)
      ctx.strokeStyle = root.stroke
      ctx.lineWidth = root.lineWidth
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.stroke()
      ctx.globalAlpha = 1

      if (root.hoverActive && root.hoverIndex >= 0 && root.hoverIndex < pts.length) {
        var p = pts[root.hoverIndex]
        ctx.beginPath()
        ctx.arc(p.x, p.y, 3.5, 0, Math.PI * 2)
        ctx.fillStyle = root.stroke
        ctx.fill()
      }
    }
  }

  MouseArea {
    id: hover
    width: root.plotWidth
    height: parent.height
    visible: root.interactive
    hoverEnabled: root.interactive
    enabled: root.interactive
    preventStealing: true
    cursorShape: Qt.CrossCursor
    onExited: {
      root.hoverActive = false
      root.hoverIndex = -1
      root.hovered(false, NaN, -1)
    }
    onPositionChanged: function(mouse) {
      var idx = root.indexAt(mouse.x)
      root.hoverIndex = idx
      root.hoverActive = idx >= 0
      root.hovered(root.hoverActive, root.hoverPrice, idx)
    }
  }

  Rectangle {
    visible: root.interactive && root.hoverActive && root.hoverIndex >= 0 && root.geo.points && root.hoverIndex < root.geo.points.length
    width: Style.space(7)
    height: Style.space(7)
    radius: width / 2
    x: (root.geo.points && root.hoverIndex >= 0 && root.hoverIndex < root.geo.points.length) ? root.geo.points[root.hoverIndex].x - width / 2 : 0
    y: (root.geo.points && root.hoverIndex >= 0 && root.hoverIndex < root.geo.points.length) ? root.geo.points[root.hoverIndex].y - height / 2 : 0
    color: root.stroke
    border.width: 1
    border.color: Color.popups.background
  }

  Rectangle {
    id: hoverBadge
    visible: root.interactive && root.hoverActive && isFinite(root.hoverPrice)
    readonly property real badgeX: {
      if (!root.geo.points || root.hoverIndex < 0 || root.hoverIndex >= root.geo.points.length) return 0
      var x = root.geo.points[root.hoverIndex].x - width / 2
      if (x < 0) return 0
      if (x > root.plotWidth - width) return Math.max(0, root.plotWidth - width)
      return x
    }
    readonly property real badgeY: {
      if (!root.geo.points || root.hoverIndex < 0 || root.hoverIndex >= root.geo.points.length) return 0
      var y = root.geo.points[root.hoverIndex].y - height - Style.space(8)
      if (y < 0) y = root.geo.points[root.hoverIndex].y + Style.space(8)
      return y
    }
    x: badgeX
    y: badgeY
    radius: height / 2
    z: 4
    color: Color.popups.background
    border.width: 1
    border.color: Util.alpha(root.stroke, 0.45)
    implicitWidth: badgeLabel.implicitWidth + Style.space(12)
    implicitHeight: badgeLabel.implicitHeight + Style.space(6)

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: Model.formatUsd(root.hoverPrice, Number(root.hoverPrice) >= 100 ? 2 : 4)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Text {
    visible: !root.compact
    anchors.right: parent.right
    anchors.top: parent.top
    width: root.axisWidth
    horizontalAlignment: Text.AlignRight
    text: root.geo.points && root.geo.points.length ? Model.formatUsd(root.geo.max, Number(root.geo.max) >= 100 ? 0 : 2) : ""
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: !root.compact
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: root.axisWidth
    horizontalAlignment: Text.AlignRight
    text: root.geo.points && root.geo.points.length ? Model.formatUsd(root.geo.min, Number(root.geo.min) >= 100 ? 0 : 2) : ""
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
