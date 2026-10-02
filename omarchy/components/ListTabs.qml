import QtQuick
import qs.Commons
import qs.Ui

// The named-list strip, following the macOS group bar's interactions: a left
// click switches, a right click offers rename and delete, and "+" becomes an
// inline name field so a list is born with its name — not created blank and
// renamed after. Drag-to-reorder is the one macOS gesture not carried over;
// a drag inside a popup that closes on outside clicks loses its own list.
Item {
  id: root

  required property var names
  required property string activeName
  required property color textColor
  required property color accentColor
  required property string panelFontFamily
  property int listCount: names ? names.length : 0

  signal selected(string name)
  signal createRequested(string name)
  signal renameRequested(string name, string newName)
  signal removeRequested(string name)

  // Which tab is being renamed inline, and whether "+" is a name field.
  property string renaming: ""
  property bool creating: false
  readonly property bool editing: creating || renaming !== ""

  function cancelEditing() {
    renaming = ""
    creating = false
  }

  implicitHeight: Style.space(24)

  Flickable {
    // Lists are user-named and unbounded; the strip scrolls rather than
    // shrinking labels into ambiguity.
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height
    contentWidth: tabRow.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Row {
      id: tabRow
      height: parent.height
      spacing: Style.space(4)

      Repeater {
        model: root.names

        Rectangle {
          id: tab
          required property string modelData
          readonly property bool active: modelData === root.activeName
          readonly property bool renaming: root.renaming === modelData

          height: parent.height
          implicitWidth: renaming
            ? renameField.width + Style.space(8)
            : tabContent.implicitWidth + Style.space(18)
          radius: 0
          color: active
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
            : tabHover.hovered
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
              : "transparent"

          HoverHandler { id: tabHover }
          TapHandler {
            enabled: !tab.renaming
            onTapped: {
              root.cancelEditing()
              root.selected(tab.modelData)
            }
            // The macOS group bar renames from a context menu; the shell's
            // idiom for "edit this label in place" is the double click.
            onDoubleTapped: {
              root.creating = false
              root.renaming = tab.modelData
            }
          }

          Row {
            id: tabContent
            visible: !tab.renaming
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              id: tabLabel
              anchors.verticalCenter: parent.verticalCenter
              text: tab.modelData
  textFormat: Text.PlainText
              color: tab.active
                ? root.textColor
                : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: tab.active
            }

            // Delete reveals on hover, the way row actions do. The last list
            // is not deletable — a strip with no tabs reads as a broken panel.
            Text {
              visible: tabHover.hovered && root.listCount > 1
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              TapHandler { onTapped: root.removeRequested(tab.modelData) }
            }
          }

          TextField {
            id: renameField
            visible: tab.renaming
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            width: Style.space(92)
            foreground: root.textColor
            text: tab.modelData
            onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
            onAccepted: {
              root.renameRequested(tab.modelData, text)
              root.renaming = ""
            }
            Keys.onEscapePressed: root.renaming = ""
          }

        }
      }

      // "+" and the name field it becomes. The list is created on submit,
      // named — Esc walks away leaving nothing behind.
      Rectangle {
        visible: !root.creating
        height: parent.height
        width: Style.space(22)
        radius: 0
        color: addHover.hovered
          ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
          : "transparent"

        HoverHandler { id: addHover }
        TapHandler {
          onTapped: {
            root.renaming = ""
            root.creating = true
          }
        }

        Text {
          anchors.centerIn: parent
          text: "+"
          color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.55)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      TextField {
        id: createField
        visible: root.creating
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(92)
        foreground: root.textColor
        placeholderText: "List name"
        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
        onAccepted: {
          if (text.replace(/^\s+|\s+$/g, "") !== "") root.createRequested(text)
          root.creating = false
        }
        Keys.onEscapePressed: root.creating = false
      }
    }
  }
}
