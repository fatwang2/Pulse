import QtQuick
import qs.Commons

// The session line at detail size: the quote's own series, so it costs no
// request, with the previous close as a dashed reference the way the macOS
// intraday chart draws it.
Canvas {
  id: root

  property var series: null
  property real previousClose: 0
  required property color lineColor
  required property color guideColor
  required property color textColor

  readonly property bool hasSeries: series && series.points && series.points.length > 1

  onSeriesChanged: requestPaint()
  onPreviousCloseChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (!hasSeries || width <= 0 || height <= 0) return

    var inset = 3
    var plotHeight = Math.max(1, height - inset * 2)
    var minimum = root.series.min
    var maximum = root.series.max
    if (root.previousClose > 0) {
      minimum = Math.min(minimum, root.previousClose)
      maximum = Math.max(maximum, root.previousClose)
    }
    var range = maximum - minimum

    function x(index) { return index * width / (root.series.points.length - 1) }
    function y(value) {
      var ratio = range > 0 ? (value - minimum) / range : 0.5
      return inset + plotHeight - ratio * plotHeight
    }

    if (root.previousClose > 0) {
      ctx.beginPath()
      ctx.setLineDash([3, 4])
      ctx.lineWidth = 1
      ctx.strokeStyle = Qt.rgba(root.guideColor.r, root.guideColor.g, root.guideColor.b, 0.35)
      ctx.moveTo(0, y(root.previousClose))
      ctx.lineTo(width, y(root.previousClose))
      ctx.stroke()
      ctx.setLineDash([])
    }

    // A soft fill under the line anchors it the way the macOS chart does,
    // derived from the line color rather than introducing a new one.
    ctx.beginPath()
    ctx.moveTo(x(0), y(root.series.points[0]))
    for (var i = 1; i < root.series.points.length; i++) {
      ctx.lineTo(x(i), y(root.series.points[i]))
    }
    ctx.lineWidth = 1.6
    ctx.strokeStyle = root.lineColor
    ctx.lineJoin = "round"
    ctx.stroke()
    ctx.lineTo(x(root.series.points.length - 1), height)
    ctx.lineTo(0, height)
    ctx.closePath()
    ctx.fillStyle = Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.10)
    ctx.fill()
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasSeries
    text: "No intraday data"
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
    font.pixelSize: Style.font.caption
  }
}
