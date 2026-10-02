import QtQuick

// The Pulse mark, drawn rather than shipped as an asset so it takes the
// surface's own foreground color and stays sharp at every bar scale.
//
// The path is the macOS menu-bar icon's, verbatim. That icon is a template
// image — macOS replaces its fill with the menu bar's foreground — so drawing
// it in the theme's color here is the same behavior, not a departure from it.
Canvas {
  id: root

  // Required rather than defaulted: a fallback hex is a color that survives
  // into production looking wrong on every theme but the one it was written
  // against. Every caller passes the surface's own foreground down.
  required property color foregroundColor

  // The macOS asset's viewBox and stroke, in its own units. Everything below
  // is expressed in them and scaled once, so the mark keeps its proportions
  // instead of being re-tuned per call site.
  readonly property real viewBoxX: 134
  readonly property real viewBoxY: 215
  readonly property real viewBoxWidth: 756
  readonly property real viewBoxHeight: 580
  readonly property real viewBoxStroke: 72

  onForegroundColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (width <= 0 || height <= 0) return

    // Fit the viewBox inside the item without distorting it, then centre what
    // is left over on the shorter axis.
    var scale = Math.min(width / viewBoxWidth, height / viewBoxHeight)
    ctx.save()
    ctx.translate((width - viewBoxWidth * scale) / 2, (height - viewBoxHeight * scale) / 2)
    ctx.scale(scale, scale)
    ctx.translate(-viewBoxX, -viewBoxY)

    ctx.strokeStyle = foregroundColor
    ctx.lineWidth = viewBoxStroke
    ctx.lineJoin = "round"
    ctx.lineCap = "round"

    // A flat lead-in, a small dip, the tall spike, the deep trough, and a flat
    // lead-out — the trace the app is named for.
    ctx.beginPath()
    ctx.moveTo(170, 512)
    ctx.lineTo(292, 512)
    ctx.bezierCurveTo(316, 512, 328, 476, 348, 476)
    ctx.bezierCurveTo(371, 476, 383, 537, 405, 537)
    ctx.bezierCurveTo(425, 537, 444, 423, 493, 278)
    ctx.bezierCurveTo(502, 251, 520, 251, 529, 280)
    ctx.lineTo(627, 728)
    ctx.bezierCurveTo(634, 759, 654, 759, 666, 730)
    ctx.lineTo(738, 520)
    ctx.bezierCurveTo(744, 503, 756, 498, 774, 498)
    ctx.lineTo(854, 498)
    ctx.stroke()

    ctx.restore()
  }
}
