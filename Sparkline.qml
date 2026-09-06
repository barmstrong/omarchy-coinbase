import QtQuick
import QtQuick.Shapes
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
  readonly property var linePoints: {
    var out = []
    var points = geo.points || []
    for (var i = 0; i < points.length; i++)
      out.push(Qt.point(Number(points[i].x), Number(points[i].y)))
    return out
  }
  readonly property var fillPoints: {
    if (linePoints.length < 2) return []
    var out = [Qt.point(linePoints[0].x, height)]
    for (var i = 0; i < linePoints.length; i++) out.push(linePoints[i])
    out.push(Qt.point(linePoints[linePoints.length - 1].x, height))
    return out
  }
  readonly property real hoverPrice: {
    if (!hoverActive || hoverIndex < 0 || !geo.values || hoverIndex >= geo.values.length) return NaN
    return Number(geo.values[hoverIndex])
  }

  signal hovered(bool active, real price, int index)

  function indexAt(x) {
    var pts = geo.points
    if (!pts || pts.length < 2) return -1
    var t = Math.max(0, Math.min(1, x / Math.max(1, plotWidth)))
    return Math.round(t * (pts.length - 1))
  }

  Shape {
    id: chartShape
    width: root.plotWidth
    height: parent.height
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    visible: root.linePoints.length >= 2

    ShapePath {
      fillColor: root.fill
      strokeColor: "transparent"
      startX: root.fillPoints.length ? root.fillPoints[0].x : 0
      startY: root.fillPoints.length ? root.fillPoints[0].y : 0
      PathPolyline { path: root.fillPoints }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.stroke
      strokeWidth: root.lineWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.linePoints.length ? root.linePoints[0].x : 0
      startY: root.linePoints.length ? root.linePoints[0].y : 0
      PathPolyline { path: root.linePoints }
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
