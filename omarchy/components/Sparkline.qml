import QtQuick

// One-session price line. It uses the same direction colour as the percentage
// beside it, with previous close as a faint guide, so the chart and number are
// two readings of the same movement rather than competing signals.
Canvas {
  id: root

  property var series: null
  property real previousClose: 0
  required property color lineColor
  required property color guideColor
  readonly property bool hasSeries: series && series.points && series.points.length > 1

  opacity: hasSeries ? 1 : 0
  antialiasing: true

  onSeriesChanged: requestPaint()
  onPreviousCloseChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onGuideColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var context = getContext("2d")
    context.reset()
    if (!hasSeries || width <= 0 || height <= 0) return

    var inset = 1.5
    var plotHeight = Math.max(1, height - inset * 2)
    var minimum = root.series.min
    var maximum = root.series.max
    if (root.previousClose > 0) {
      minimum = Math.min(minimum, root.previousClose)
      maximum = Math.max(maximum, root.previousClose)
    }
    var range = maximum - minimum

    function x(index) {
      return index * width / (root.series.points.length - 1)
    }
    function y(value) {
      var ratio = range > 0 ? (value - minimum) / range : 0.5
      return inset + plotHeight - ratio * plotHeight
    }

    if (root.previousClose > 0) {
      context.beginPath()
      context.setLineDash([2, 3])
      context.lineWidth = 1
      context.strokeStyle = Qt.rgba(root.guideColor.r, root.guideColor.g, root.guideColor.b, 0.35)
      context.moveTo(0, y(root.previousClose))
      context.lineTo(width, y(root.previousClose))
      context.stroke()
      context.setLineDash([])
    }

    context.beginPath()
    context.moveTo(x(0), y(root.series.points[0]))
    for (var i = 1; i < root.series.points.length; i++) {
      context.lineTo(x(i), y(root.series.points[i]))
    }
    context.lineWidth = 1.4
    context.strokeStyle = root.lineColor
    context.lineJoin = "round"
    context.stroke()
  }
}
