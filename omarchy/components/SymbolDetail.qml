import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The quote detail: price, the chart at reading size, then the facts in the
// order someone asks for them — what it did today, and where the number came
// from. Provenance is not an afterthought: a delayed price and a real-time
// price look identical until the panel says which one this is.
Column {
  id: root

  required property var row
  required property var candleStore
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily
  property double nowMs: 0

  signal dismissed()

  readonly property var quote: row ? row.quote : null
  readonly property bool hasQuote: !!quote
  readonly property real changePercent: row ? Number(row.changePercent || 0) : 0
  readonly property color movementColor: !hasQuote
    ? mutedColor
    : (changePercent > 0 ? riseColor : (changePercent < 0 ? fallColor : textColor))

  // Which chart the detail shows. Intraday is the quote's own series and
  // costs nothing; the candle periods fetch through the store on first look.
  property string chartPeriod: "intraday"

  function ensureCandles() {
    if (!root.row || root.chartPeriod === "intraday") return
    root.candleStore.ensure(root.row.key, root.chartPeriod)
  }

  onChartPeriodChanged: ensureCandles()

  // Reset to the session view only when the instrument changes. The row
  // object itself is rebuilt on every price tick, so watching the object
  // would snap a candle chart back to intraday seconds after it was chosen.
  property string _shownKey: ""
  onRowChanged: {
    var key = root.row ? root.row.key : ""
    if (key !== root._shownKey) {
      root._shownKey = key
      root.chartPeriod = "intraday"
    }
  }
  onVisibleChanged: if (visible) ensureCandles()

  function fieldText(value) {
    return (typeof value === "number" && isFinite(value)) ? Model.formatPrice(value) : "—"
  }

  function delayText() {
    if (!hasQuote) return "—"
    var delay = quote.sourceDelaySeconds
    if (delay === null || delay === undefined) return "unknown"
    if (delay <= 0) return "real time"
    return "delayed " + Math.round(delay / 60) + " min"
  }

  function timestampText() {
    if (!hasQuote || !quote.timestampMs) return "—"
    return Qt.formatDateTime(new Date(quote.timestampMs), "yyyy-MM-dd HH:mm:ss")
  }

  spacing: Style.space(10)

  component Field: Item {
    required property string label
    required property string value
    property color valueColor: root.textColor
    implicitHeight: Style.space(26)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      textFormat: Text.PlainText
      color: root.mutedColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      textFormat: Text.PlainText
      color: parent.valueColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  // --- Price block ----------------------------------------------------------

  Item {
    width: parent.width
    implicitHeight: Style.space(46)

    Column {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        text: root.row ? root.row.displayCode : ""
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        text: (root.row && root.row.name) ? String(root.row.name).toUpperCase() : "—"
        textFormat: Text.PlainText
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        anchors.right: parent.right
        text: root.hasQuote ? Model.formatPrice(root.quote.price) : "—"
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        text: root.hasQuote
          ? (Model.formatChange(root.row.change) + "  " + Model.formatPercent(root.row.changePercent))
          : "—"
        textFormat: Text.PlainText
        color: root.movementColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // --- Chart ----------------------------------------------------------------

  ButtonGroup {
    width: parent.width
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    options: [
      { value: "intraday", label: "1D" },
      { value: "day", label: "D" },
      { value: "week", label: "W" },
      { value: "month", label: "M" }
    ]
    value: root.chartPeriod
    onChanged: function (period) { root.chartPeriod = period }
  }

  IntradayChart {
    visible: root.chartPeriod === "intraday"
    width: parent.width
    height: Style.space(120)
    series: root.hasQuote ? root.quote.series : null
    previousClose: root.hasQuote ? Number(root.quote.previousClose || 0) : 0
    lineColor: root.movementColor
    guideColor: root.textColor
    textColor: root.textColor
  }

  CandleChart {
    visible: root.chartPeriod !== "intraday"
    width: parent.width
    height: Style.space(120)
    candles: root.row ? root.candleStore.candlesFor(root.row.key, root.chartPeriod) : null
    loading: root.row ? root.candleStore.loading(root.row.key, root.chartPeriod) : false
    riseColor: root.riseColor
    fallColor: root.fallColor
    textColor: root.textColor
  }

  PanelSeparator { foreground: root.textColor }

  // --- Session facts --------------------------------------------------------

  Column {
    width: parent.width

    Field { width: parent.width; label: "Open"; value: root.fieldText(root.hasQuote ? root.quote.open : null) }
    Field { width: parent.width; label: "High"; value: root.fieldText(root.hasQuote ? root.quote.high : null) }
    Field { width: parent.width; label: "Low"; value: root.fieldText(root.hasQuote ? root.quote.low : null) }
    Field {
      width: parent.width
      label: "Amplitude"
      value: (root.row && typeof root.row.amplitudePercent === "number")
        ? root.row.amplitudePercent.toFixed(2) + "%"
        : "—"
    }
    Field {
      width: parent.width
      label: "Prev close"
      value: root.fieldText(root.hasQuote ? root.quote.previousClose : null)
    }
    Field {
      width: parent.width
      label: "Volume"
      value: root.hasQuote ? Model.formatVolume(root.quote.volume) : "—"
    }
    // The last completed regular session, shown only when the live price is
    // from some other session — otherwise it would repeat the line above it.
    Field {
      width: parent.width
      visible: root.hasQuote && !!root.quote.regularSession
      label: "At the close"
      value: (root.hasQuote && root.quote.regularSession)
        ? (Model.formatPrice(root.quote.regularSession.price)
           + "  " + Model.formatPercent(root.row.regularChangePercent))
        : "—"
      valueColor: (root.row && typeof root.row.regularChangePercent === "number")
        ? (root.row.regularChangePercent > 0
            ? root.riseColor
            : (root.row.regularChangePercent < 0 ? root.fallColor : root.textColor))
        : root.textColor
    }
  }

  PanelSeparator { foreground: root.textColor }

  // --- Provenance -----------------------------------------------------------

  Column {
    width: parent.width

    Field {
      width: parent.width
      label: "Currency"
      value: root.hasQuote ? String(root.quote.currencyCode || "—") : "—"
    }
    Field {
      width: parent.width
      label: "Source"
      value: root.hasQuote
        ? (String(root.quote.sourceName || "—") + " · " + root.delayText())
        : "—"
    }
    Field { width: parent.width; label: "As of"; value: root.timestampText() }
  }

}
