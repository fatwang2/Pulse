import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// One instrument, laid out the way the macOS popover lays it out: name over
// badge-and-code on the left, the session line in the middle, price over
// change on the right.
//
// The identity column is capped, not elastic — the chart is the reading this
// panel exists for, so it gets the slack. A name that does not fit elides, and
// hovering the row for a moment shows it in full (PanelToolTip's own delay),
// which trades a rare hover for chart width on every row.
Rectangle {
  id: root

  required property var row
  required property color textColor
  required property color riseColor
  required property color fallColor
  required property color mutedColor
  required property string panelFontFamily
  property bool selected: false
  property bool striped: false
  property double nowMs: 0
  property bool pinned: false
  // Edit mode is the only surface with controls: reorder, pin and remove
  // appear at the row's edge while it is on, and nothing appears on hover —
  // reading the list and editing the list are different postures, entered
  // deliberately from the header.
  property bool editMode: false
  property bool canMoveUp: false
  property bool canMoveDown: false
  // Named so the remove tooltip can say what it removes from — "Remove from
  // Watching" is a different promise than "Remove".
  property string listName: ""

  signal activated()
  signal moveRequested(int delta)
  signal removeRequested()
  signal pinRequested()

  readonly property var quote: row.quote
  readonly property bool hasQuote: !!quote
  readonly property bool stale: hasQuote && Model.isStale(quote, nowMs)
  readonly property real changePercent: Number(row.changePercent || 0)
  // Flat is not a rise. A zero change takes the neutral foreground so the eye
  // is not told something moved when nothing did.
  readonly property color movementColor: !hasQuote
    ? mutedColor
    : (changePercent > 0 ? riseColor : (changePercent < 0 ? fallColor : textColor))
  readonly property string sessionLabel: Model.sessionLabel(quote)
  readonly property string primaryName: row.name ? String(row.name) : row.displayCode
  readonly property bool nameElided: nameText.truncated

  width: ListView.view ? ListView.view.width : implicitWidth
  implicitHeight: Style.space(42)
  radius: 0
  color: selected
    ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.10)
    : hover.hovered
      ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.05)
      : striped
        ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.025)
        : "transparent"

  HoverHandler { id: hover }
  TapHandler {
    enabled: !root.editMode
    onTapped: root.activated()
  }



  Column {
    id: identity
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    // The cap: enough for "Tencent Holdings…" to be recognizable, no more.
    width: Style.space(118)
    spacing: Style.space(3)

    Row {
      width: parent.width
      spacing: Style.space(4)

      Text {
        id: nameText
        width: Math.min(implicitWidth, parent.width - (pinMark.visible ? Style.space(14) : 0))
        text: root.primaryName
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight

        // The full name, on demand — from the name itself, not the row. A
        // pointer crossing the chart on its way to the price should not
        // raise a caption; pointing at the truncated text is the question
        // the tooltip answers. And only when it actually elided: repeating
        // what the row shows is noise on every hover.
        HoverHandler { id: nameHover }
        PlainToolTip {
          visible: nameHover.hovered && root.nameElided
          text: root.primaryName
        }
      }

      // The macOS pin.fill, tertiary: pinned is a fact about the row, read
      // at a glance and never the only signal — the row also sits atop its
      // market block.
      Text {
        id: pinMark
        visible: root.pinned
        anchors.verticalCenter: nameText.verticalCenter
        text: "󰐃"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.40)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      spacing: Style.space(5)

      MarketBadge {
        anchors.verticalCenter: parent.verticalCenter
        label: root.row.marketLabel
        textColor: root.textColor
        panelFontFamily: root.panelFontFamily
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        // The code identifies; the name above may be missing or elided, and
        // an error takes this slot because it is what there is to say.
        text: root.row.error ? root.row.error : root.row.displayCode
        textFormat: Text.PlainText
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.max(0, identity.width - Style.space(34))
      }
    }
  }

  // The chart takes everything between the two fixed columns.
  Sparkline {
    id: chart
    anchors.left: identity.right
    anchors.leftMargin: Style.space(10)
    anchors.right: root.editMode ? editActions.left : figures.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(24)
    series: root.hasQuote ? root.quote.series : null
    previousClose: root.hasQuote ? Number(root.quote.previousClose || 0) : 0
    lineColor: root.movementColor
    guideColor: root.textColor
  }

  // The edit-mode controls, in the figures' place at the row's right edge.
  // Move sits here legally because edit mode bypasses the schedule order:
  // the arrows edit exactly the sequence the rows are showing.
  Row {
    id: editActions
    visible: root.editMode
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    PanelActionButton {
      enabled: root.canMoveUp
      opacity: enabled ? 1.0 : 0.3
      iconText: "󰜷"
      tooltipText: "Move up"
      foreground: root.mutedColor
      fontFamily: root.panelFontFamily
      onClicked: root.moveRequested(-1)
    }
    PanelActionButton {
      enabled: root.canMoveDown
      opacity: enabled ? 1.0 : 0.3
      iconText: "󰜮"
      tooltipText: "Move down"
      foreground: root.mutedColor
      fontFamily: root.panelFontFamily
      onClicked: root.moveRequested(1)
    }
    PanelActionButton {
      iconText: root.pinned ? "󰤰" : "󰐃"
      tooltipText: root.pinned ? "Unpin" : "Pin to top of its market"
      foreground: root.pinned ? root.textColor : root.mutedColor
      fontFamily: root.panelFontFamily
      onClicked: root.pinRequested()
    }
    PanelActionButton {
      iconText: "󰩺"
      tooltipText: "Remove from this list"
      foreground: root.mutedColor
      fontFamily: root.panelFontFamily
      onClicked: root.removeRequested()
    }
  }

  Column {
    id: figures
    visible: !root.editMode
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(96)
    spacing: Style.space(3)

    Row {
      anchors.right: parent.right
      spacing: Style.space(5)

      // Session marker sits beside the price the way "Pre" does on macOS.
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.sessionLabel !== ""
        text: root.sessionLabel
        textFormat: Text.PlainText
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasQuote ? Model.formatPrice(root.quote.price) : "—"
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        // A price that has stopped arriving is dimmed rather than hidden: the
        // last known number is still the best answer available.
        opacity: root.stale ? 0.55 : 1.0
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.stale
        text: "STALE"
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.40)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasQuote ? Model.formatPercent(root.row.changePercent) : "—"
        textFormat: Text.PlainText
        color: root.movementColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
