import QtQuick
import qs.Commons

// Feed state, sitting where a refresh button would be. The panel either has
// current prices or says why it does not, and both answers are readable at a
// glance. The label carries the state for anyone who cannot separate the
// colors, so color is never the only indicator.
Row {
  id: root

  required property color textColor
  required property color liveColor
  required property color errorColor
  required property string panelFontFamily
  property string status: "idle"

  readonly property bool live: status === "live"
  readonly property bool loading: status === "loading"
  readonly property bool failed: status === "error"

  spacing: Style.space(5)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(6)
    height: width
    radius: width / 2
    color: root.live
      ? root.liveColor
      : root.failed
        ? root.errorColor
        : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.30)

    SequentialAnimation on opacity {
      running: root.loading
      loops: Animation.Infinite
      NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.live ? "LIVE" : (root.loading ? "LOADING" : (root.failed ? "OFFLINE" : "IDLE"))
    textFormat: Text.PlainText
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, root.live ? 0.70 : 0.45)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
  }
}
