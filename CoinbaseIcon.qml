import QtQuick
import QtQuick.Shapes
import qs.Commons

// Official Coinbase C: a ring with a rectangular mouth at 3 o'clock.
// Ratios from the 128px favicon — outer 53, inner 27, slot 14.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real size: Math.min(width, height)
  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real outer: size * 0.46
  readonly property real inner: outer * (27 / 53)
  readonly property real slot: outer * (14 / 53)
  readonly property real slotHalf: slot / 2
  readonly property real slotOuterX: cx + Math.sqrt(Math.max(0, outer * outer - slotHalf * slotHalf))
  readonly property real slotAngle: (outer > 0 && slotHalf < outer)
    ? Math.asin(slotHalf / outer) * 180 / Math.PI
    : 0

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      fillRule: ShapePath.OddEvenFill

      startX: root.cx + root.outer
      startY: root.cy
      PathAngleArc {
        centerX: root.cx
        centerY: root.cy
        radiusX: root.outer
        radiusY: root.outer
        startAngle: 0
        sweepAngle: 360
      }

      PathMove {
        x: root.cx + root.inner
        y: root.cy
      }
      PathAngleArc {
        centerX: root.cx
        centerY: root.cy
        radiusX: root.inner
        radiusY: root.inner
        startAngle: 0
        sweepAngle: 360
      }

      PathMove {
        x: root.cx + root.inner
        y: root.cy - root.slotHalf
      }
      PathLine {
        x: root.slotOuterX
        y: root.cy - root.slotHalf
      }
      PathAngleArc {
        centerX: root.cx
        centerY: root.cy
        radiusX: root.outer
        radiusY: root.outer
        startAngle: -root.slotAngle
        sweepAngle: 2 * root.slotAngle
      }
      PathLine {
        x: root.cx + root.inner
        y: root.cy + root.slotHalf
      }
      PathLine {
        x: root.cx + root.inner
        y: root.cy - root.slotHalf
      }
    }
  }
}
