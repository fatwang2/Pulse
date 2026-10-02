import QtQuick
import qs.Commons

// Daily / weekly / monthly candlesticks with a volume strip, the way the
// macOS detail draws them. Rises hollow up-color, falls filled down-color —
// and since a candle's direction is also its body's fill, the colors carry a
// redundant shape signal for anyone who cannot separate them.
Canvas {
  id: root

  property var candles: null
  required property color riseColor
  required property color fallColor
  required property color textColor
  property bool loading: false

  readonly property bool hasCandles: candles && candles.length > 1
  // The volume strip takes the bottom fifth; price gets the rest.
  readonly property real volumeShare: 0.2

  opacity: hasCandles ? 1 : 0.4

  onCandlesChanged: requestPaint()
  onRiseColorChanged: requestPaint()
  onFallColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (!hasCandles || width <= 0 || height <= 0) return

    var count = candles.length
    var priceHeight = height * (1 - volumeShare) - 4
    var volumeTop = height * (1 - volumeShare)
    var volumeHeight = height * volumeShare

    var min = Infinity, max = -Infinity, maxVolume = 0
    for (var i = 0; i < count; i++) {
      min = Math.min(min, candles[i].low)
      max = Math.max(max, candles[i].high)
      maxVolume = Math.max(maxVolume, candles[i].volume)
    }
    var range = max - min
    if (range <= 0) range = max || 1

    // Candle geometry: the slot is the width one candle owns; the body fills
    // most of it and never goes below one pixel, so a dense 126-candle chart
    // still reads as bars rather than fog.
    var slot = width / count
    var bodyWidth = Math.max(1, Math.floor(slot * 0.7))

    function x(index) { return index * slot + slot / 2 }
    function y(value) { return 2 + priceHeight - ((value - min) / range) * priceHeight }

    for (var j = 0; j < count; j++) {
      var candle = candles[j]
      var up = candle.close >= candle.open
      var color = up ? root.riseColor : root.fallColor
      var cx = Math.round(x(j))

      // Wick, always one pixel: high to low.
      ctx.strokeStyle = color
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(cx + 0.5, y(candle.high))
      ctx.lineTo(cx + 0.5, y(candle.low))
      ctx.stroke()

      // Body. A doji's body would round to zero height; it gets one pixel so
      // the session still exists on screen.
      var top = y(Math.max(candle.open, candle.close))
      var bottom = y(Math.min(candle.open, candle.close))
      var bodyHeight = Math.max(1, bottom - top)
      var left = cx - bodyWidth / 2
      if (up && bodyWidth >= 3) {
        ctx.strokeStyle = color
        ctx.strokeRect(left + 0.5, top + 0.5, bodyWidth - 1, Math.max(1, bodyHeight - 1))
      } else {
        ctx.fillStyle = color
        ctx.fillRect(left, top, bodyWidth, bodyHeight)
      }

      // Volume, dimmed so it reads as context rather than a second chart.
      if (maxVolume > 0 && candle.volume > 0) {
        var vh = Math.max(1, (candle.volume / maxVolume) * (volumeHeight - 2))
        ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.45)
        ctx.fillRect(left, height - vh, bodyWidth, vh)
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasCandles
    text: root.loading ? "Loading…" : "No history"
    textFormat: Text.PlainText
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
    font.pixelSize: Style.font.caption
  }
}
