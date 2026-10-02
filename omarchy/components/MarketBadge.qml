import QtQuick
import qs.Commons

// The venue a row trades on. Shanghai and Shenzhen share one badge, as do the
// two Korean boards: which board a symbol sits on is already in its suffix, and
// splitting the badge would add a distinction nobody reads a watchlist for.
Rectangle {
  id: root

  required property string label
  required property color textColor
  required property string panelFontFamily

  implicitWidth: text.implicitWidth + Style.space(8)
  implicitHeight: Style.space(14)
  radius: 0
  color: "transparent"
  border.width: 1
  border.color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.20)

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    textFormat: Text.PlainText
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
  }
}
