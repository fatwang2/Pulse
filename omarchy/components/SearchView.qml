import QtQuick
import qs.Commons
import qs.Ui
import "../Market.js" as Market

// The search page, replacing the watchlist while search is active — the way
// the macOS popover swaps the two. The tabs above stay: results add to the
// active list, and switching lists leaves search. An empty query shows the
// recent searches; typing swaps them for live results, and adding keeps the
// page open so several symbols can land in one visit.
Column {
  id: root

  required property var watchlist
  required property var search
  required property color textColor
  required property color mutedColor
  required property string panelFontFamily

  signal dismissed()

  function focusInput() {
    queryField.forceActiveFocus()
  }

  // Scripted entry (IPC) goes through the same field the keyboard uses, so
  // the page's empty/results state always follows what the field shows.
  function setQuery(text) {
    queryField.text = text
  }

  function clear() {
    queryField.text = ""
    root.search.clear()
  }

  readonly property bool queryEmpty: String(queryField.text).replace(/^\s+|\s+$/g, "") === ""

  spacing: Style.space(8)
  bottomPadding: Math.max(0, Style.space(320) - implicitHeight + bottomPadding)

  TextField {
    id: queryField
    width: parent.width
    placeholderText: "Search name or code — nvidia, 600519.SH, 7203.T"
    onTextChanged: root.search.query = text
    Keys.onEscapePressed: {
      root.clear()
      root.dismissed()
    }
  }

  // --- Empty query: the recent searches, as chips. -------------------------

  Column {
    width: parent.width
    visible: root.queryEmpty && root.watchlist.recentSearches.length > 0
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Style.space(16)

      PanelSectionHeader {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "RECENT"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Clear"
        color: root.mutedColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        TapHandler { onTapped: root.watchlist.clearRecentSearches() }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: root.watchlist.recentSearches

        Rectangle {
          id: chip
          required property string modelData
          implicitWidth: chipLabel.implicitWidth + Style.space(14)
          implicitHeight: Style.space(20)
          radius: 0
          color: chipHover.hovered
            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.10)
            : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.05)
          border.width: 1
          border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)

          HoverHandler { id: chipHover }
          TapHandler {
            onTapped: {
              // Re-recording moves the query back to the front, like macOS.
              root.watchlist.recordRecentSearch(chip.modelData)
              queryField.text = chip.modelData
            }
          }

          Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.modelData
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    visible: root.queryEmpty && root.watchlist.recentSearches.length === 0
    text: "Search across US, HK, China A, Japan and Korea by name, or by any code."
    color: root.mutedColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // --- Results. -------------------------------------------------------------

  Text {
    width: parent.width
    visible: !root.queryEmpty && (root.search.searching || root.search.message !== "")
    text: root.search.searching ? "Searching…" : root.search.message
    textFormat: Text.PlainText
    color: root.mutedColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Column {
    width: parent.width
    visible: !root.queryEmpty && root.search.results.length > 0
    spacing: 0

    Repeater {
      // The page is search's alone now, so it can carry a real list.
      model: root.search.results.slice(0, 10)

      Rectangle {
        id: resultRow
        required property var modelData
        required property int index
        readonly property bool alreadyAdded: root.watchlist.contains(modelData.key)

        width: parent.width
        implicitHeight: Style.space(34)
        radius: 0
        color: resultHover.hovered
          ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
          : (index % 2 === 1
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.025)
              : "transparent")

        HoverHandler { id: resultHover }
        TapHandler {
          enabled: !resultRow.alreadyAdded
          onTapped: {
            if (root.watchlist.addSymbol(resultRow.modelData.key)) {
              // The query earned its place in the recents by producing an
              // add; the page stays open so the next symbol can follow.
              root.watchlist.recordRecentSearch(String(queryField.text).replace(/^\s+|\s+$/g, ""))
            }
          }
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: addedMark.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: resultRow.modelData.displayCode
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          MarketBadge {
            anchors.verticalCenter: parent.verticalCenter
            label: Market.displayLabel(resultRow.modelData.market)
            textColor: root.textColor
            panelFontFamily: root.panelFontFamily
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, resultRow.width - Style.space(170))
            text: resultRow.modelData.name ? String(resultRow.modelData.name) : "Add by code"
            textFormat: Text.PlainText
            color: root.mutedColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // A symbol already on the active list says so rather than offering an
        // add that would silently do nothing.
        Text {
          id: addedMark
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: resultRow.alreadyAdded ? "ON LIST" : "+"
          textFormat: Text.PlainText
          color: resultRow.alreadyAdded ? root.mutedColor : root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
