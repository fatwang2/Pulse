import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "SessionOrder.js" as SessionOrder
import "components"

// Pulse for Omarchy.
//
// The panel follows the macOS popover's order: identity and tools in the
// header, named lists as tabs, then the rows, with the feed's state as the
// footer. Search-to-add hangs off the header's magnifier the way it does on
// macOS; settings is for how the plugin behaves, not what it watches.
Panel {
  id: root
  moduleName: "pulse.omarchy"
  ipcTarget: "pulse.omarchy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool settingsOpen: false
  property bool searchOpen: false
  // Edit mode, entered from the header. While on, the schedule order is
  // bypassed so the arrows edit exactly the sequence the rows show — the one
  // rule that makes a move control honest — and the rows grow their reorder,
  // pin and remove controls.
  property bool editMode: false
  property var marketState: Model.initialState()
  // What the rows show: the schedule-aware order — market blocks led by the
  // session trading now, pins atop their own block — unless the user turned
  // the schedule off, in which case the saved sequence stands.
  readonly property var displayedSymbols: (watchlist.prioritizeOpenMarkets && !root.editMode)
    ? SessionOrder.orderedSymbols(watchlist.activeSymbols, watchlist.activePinnedSymbols, root.nowMs)
    : watchlist.activeSymbols
  readonly property var quoteRows: Model.rowsForSymbols(marketState, displayedSymbols)
  property double nowMs: Date.now()

  // The bar label follows the rows, so a carousel and a pinned quote read from
  // the same prices the panel shows rather than fetching their own. They read
  // across every list — the bar has no active tab.
  property int carouselIndex: 0
  readonly property var pricedRows: Model.rowsForSymbols(marketState, watchlist.allSymbols)
    .filter(function (row) { return !!row.quote })
  readonly property var pinnedRow: {
    if (watchlist.barDisplay === "carousel") {
      return pricedRows.length > 0 ? pricedRows[carouselIndex % pricedRows.length] : null
    }
    if (watchlist.barDisplay !== "pinned") return null
    for (var i = 0; i < pricedRows.length; i++) {
      if (pricedRows[i].key === watchlist.pinnedSymbol) return pricedRows[i]
    }
    // A pinned symbol with no quote yet falls back to the first priced row
    // rather than showing nothing: an empty bar slot reads as a broken widget.
    return pricedRows.length > 0 ? pricedRows[0] : null
  }
  readonly property bool showsLabel: watchlist.barDisplay !== "icon" && pinnedRow !== null
  readonly property string barLabel: pinnedRow
    ? (pinnedRow.displayCode + "  " + Model.formatPrice(pinnedRow.quote.price)
       + "  " + Model.formatPercent(pinnedRow.changePercent))
    : ""

  function closeSubviews() {
    root.settingsOpen = false
    root.searchOpen = false
    root.editMode = false
    searchView.clear()
    watchlistView.detailOpen = false
  }

  function openSearch() {
    root.settingsOpen = false
    root.editMode = false
    watchlistView.detailOpen = false
    root.searchOpen = true
    searchView.focusInput()
  }

  ThemePalette {
    id: palette
    fallbackRise: Color.accent
    fallbackFall: root.urgent
  }

  Watchlist { id: watchlist }

  SymbolSearch { id: symbolSearch }

  CandleStore { id: candleStore }

  // The panel is the reason to fetch, but not the only one: a pinned or
  // carousel bar label needs prices whether or not anything is open. The feed
  // subscribes to every list, so switching tabs shows prices instead of an
  // empty list that has to refetch.
  QuoteFeed {
    id: feed
    active: root.opened || watchlist.barDisplay !== "icon"
    symbols: watchlist.allSymbols
    pollIntervalSeconds: watchlist.pollIntervalSeconds
    onQuoteReceived: function (quote) { root.marketState = Model.applyQuote(root.marketState, quote) }
    onQuoteFailed: function (symbol, message) { root.marketState = Model.applyError(root.marketState, symbol, message) }
  }

  // The reducer state's membership follows the union of all lists.
  Connections {
    target: watchlist
    function onConfigChanged() {
      root.marketState = Model.applySymbols(root.marketState, watchlist.allSymbols)
    }
  }

  // Drives the stale marker. Thirty seconds is finer than the five-minute
  // staleness threshold it feeds, so a row crosses over within one tick of
  // actually being stale. Read again at open time — the shell can have been
  // running for days, and the first tick would otherwise be half a minute late.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: {
    if (root.opened) root.nowMs = Date.now()
    else root.closeSubviews()
  }

  Timer {
    interval: Math.max(2, watchlist.carouselIntervalSeconds) * 1000
    running: watchlist.barDisplay === "carousel" && root.pricedRows.length > 1
    repeat: true
    onTriggered: root.carouselIndex = (root.carouselIndex + 1) % Math.max(1, root.pricedRows.length)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { feed.refresh(); return "ok" }
    function settings(): string {
      root.settingsOpen = !root.settingsOpen
      return root.settingsOpen ? "open" : "closed"
    }
    // Drives the add search without synthetic keystrokes, which is how it gets
    // exercised from a script or a test run.
    function find(query: string): string {
      root.openSearch()
      searchView.setQuery(query)
      return "searching"
    }
    function results(): string {
      return JSON.stringify({
        query: symbolSearch.query,
        searching: symbolSearch.searching,
        message: symbolSearch.message,
        results: symbolSearch.results.map(function (r) {
          return { key: r.key, market: r.market, type: r.type, name: r.name }
        })
      })
    }
    function add(symbol: string): string {
      return watchlist.addSymbol(symbol) ? "added" : "rejected"
    }
    function remove(symbol: string): string {
      return watchlist.removeSymbol(symbol) ? "removed" : "not on the list"
    }
    // Opens one row's detail — the scripted stand-in for clicking it.
    function detail(symbol: string): string {
      var key = watchlist.canonical(symbol)
      for (var i = 0; i < root.quoteRows.length; i++) {
        if (root.quoteRows[i].key === key) {
          root.settingsOpen = false
          watchlistView.selectedIndex = i
          watchlistView.detailOpen = true
          return "open"
        }
      }
      return "not on the active list"
    }
    function chartPeriod(period: string): string {
      if (!watchlistView.detailOpen) return "no detail open"
      detailView.chartPeriod = period
      return detailView.chartPeriod
    }
    function edit(): string {
      root.editMode = !root.editMode
      return root.editMode ? "editing" : "done"
    }
    function lists(): string { return JSON.stringify(watchlist.listNames) }
    function selectList(name: string): string {
      return watchlist.selectList(name) ? "selected" : "no such list"
    }
    function status(): string {
      return JSON.stringify({
        lists: watchlist.listNames,
        activeList: watchlist.activeList,
        symbols: watchlist.activeSymbols,
        allSymbols: watchlist.allSymbols,
        quoted: Object.keys(root.marketState.quotes).length,
        errors: root.marketState.errors,
        feed: feed.status,
        barDisplay: watchlist.barDisplay,
        settingsOpen: root.settingsOpen,
        searchOpen: root.searchOpen,
        config: watchlist.configPath,
        configError: watchlist.error
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showsLabel ? root.barLabel : ""
    labelVisible: root.showsLabel
    hasVisualContent: true
    // The icon form takes the bar's square icon slot; a quote label is as wide
    // as the quote, so it opts out of the fixed slot rather than eliding a
    // price down to nothing.
    fixedWidth: (root.showsLabel && !vertical) ? -1 : slotSize
    fontSize: root.showsLabel ? Style.font.body : Style.bar.iconFont
    // The label is colored by direction, but the panel behind it always spells
    // the number out — color is the fast read, never the only one.
    foreground: root.showsLabel && root.pinnedRow
      ? (root.pinnedRow.changePercent > 0
          ? palette.rise
          : (root.pinnedRow.changePercent < 0 ? palette.fall : root.foreground))
      : root.foreground
    iconComponent: root.showsLabel ? null : iconMark
    tooltipText: root.showsLabel ? "Pulse" : (root.pricedRows.length > 0 ? root.barLabel || "Pulse" : "Pulse")
    active: false
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) feed.refresh()
    }
  }

  Component {
    id: iconMark
    Item {
      PulseLogo {
        anchors.centerIn: parent
        width: Style.space(13)
        height: width
        foregroundColor: root.foreground
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a text editor holds focus every key belongs to it, including the
      // panel's own single-letter shortcuts.
      blocked: root.searchOpen || root.settingsOpen || listTabs.editing
      onMoveRequested: function (dx, dy) { if (dy !== 0) watchlistView.moveSelection(dy) }
      onActivateRequested: {
        if (watchlistView.rows.length > 0) watchlistView.detailOpen = true
      }
      onCloseRequested: {
        if (root.editMode) root.editMode = false
        else if (root.searchOpen) { root.searchOpen = false; searchView.clear() }
        else if (root.settingsOpen) root.settingsOpen = false
        else if (watchlistView.detailOpen) watchlistView.detailOpen = false
        else root.close()
      }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (text) {
        var key = String(text || "").toLowerCase()
        if (root.editMode) { if (key === "e") root.editMode = false; return }
        if (key === "/" || key === "f" || key === "a") root.openSearch()
        else if (key === "r") feed.refresh()
        else if (key === "s") { watchlistView.detailOpen = false; root.searchOpen = false; searchView.clear(); root.settingsOpen = true }
        else if (key === "e" && !watchlistView.detailOpen) { root.searchOpen = false; searchView.clear(); root.editMode = true }
        else if (key >= "1" && key <= "9") {
          var names = watchlist.listNames
          var index = Number(key) - 1
          if (index < names.length) watchlist.selectList(names[index])
        }
      }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // --- Header: identity left, tools right, like the macOS popover. ---
        Item {
          id: header
          width: parent.width
          implicitHeight: Style.space(30)

          // The left edge is identity on the main page and navigation in a
          // subview: back sits where reading starts, and the title names
          // where you are — the way macOS navigation does it.
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            spacing: Style.space(7)

            readonly property bool inSubview: watchlistView.detailOpen || root.settingsOpen || root.editMode

            PanelActionButton {
              visible: parent.inSubview
              iconText: "󰁍"
              tooltipText: "Back (Esc)"
              foreground: root.muted
              fontFamily: root.fontFamily
              onClicked: {
                if (root.editMode) root.editMode = false
                else if (root.settingsOpen) root.settingsOpen = false
                else watchlistView.detailOpen = false
              }
            }

            PulseLogo {
              visible: !parent.inSubview
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(15)
              height: width
              // The macOS popover draws this mark in the system accent color
              // (PulseWaveformMark(primaryColor: .accentColor)); the theme's
              // accent role is that color's name here. The bar icon stays
              // foreground — that one mirrors the template menu-bar icon.
              foregroundColor: Color.accent
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: parent.inSubview
                ? (root.editMode
                    ? "Edit " + watchlist.activeList
                    : (root.settingsOpen
                        ? "Settings"
                        : (watchlistView.selectedRow ? watchlistView.selectedRow.displayCode : "")))
                : "Pulse"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Row {
            id: headerTools
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            spacing: Style.space(2)

            PanelActionButton {
              visible: !root.settingsOpen && !watchlistView.detailOpen && !root.editMode
              iconText: "󰍉"
              tooltipText: "Search (/)"
              foreground: root.searchOpen ? root.foreground : root.muted
              fontFamily: root.fontFamily
              onClicked: root.searchOpen ? (function () { root.searchOpen = false; searchView.clear() })() : root.openSearch()
            }

            PanelActionButton {
              visible: !root.settingsOpen && !watchlistView.detailOpen && !root.editMode
              iconText: "󰏫"
              tooltipText: "Edit list (e)"
              foreground: root.muted
              fontFamily: root.fontFamily
              onClicked: {
                root.searchOpen = false
                searchView.clear()
                root.editMode = true
              }
            }

            PanelActionButton {
              visible: !root.settingsOpen && !root.editMode
              iconText: "󰒓"
              tooltipText: "Settings (s)"
              foreground: root.muted
              fontFamily: root.fontFamily
              onClicked: {
                watchlistView.detailOpen = false
                root.searchOpen = false
                searchView.clear()
                root.settingsOpen = true
              }
            }
          }
        }

        // --- Named lists. ---
        ListTabs {
          id: listTabs
          visible: !root.settingsOpen && !watchlistView.detailOpen
          enabled: !root.editMode
          opacity: root.editMode ? 0.45 : 1
          width: parent.width
          names: watchlist.listNames
          activeName: watchlist.activeList
          textColor: root.foreground
          accentColor: Color.accent
          panelFontFamily: root.fontFamily
          onSelected: function (name) {
            // Switching lists leaves search, the way the macOS group bar does.
            root.searchOpen = false
            searchView.clear()
            watchlist.selectList(name)
          }
          onCreateRequested: function (name) { watchlist.addList(name) }
          onRenameRequested: function (name, newName) { watchlist.renameList(name, newName) }
          onRemoveRequested: function (name) { watchlist.removeList(name) }
        }

        // The search page, standing in for the watchlist while active — the
        // macOS swap. The tabs above it stay live: results add to the active
        // list, and switching lists returns to it.
        SearchView {
          id: searchView
          visible: root.searchOpen && !root.settingsOpen && !watchlistView.detailOpen
          width: parent.width
          watchlist: watchlist
          search: symbolSearch
          textColor: root.foreground
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
          onDismissed: root.searchOpen = false
        }

        WatchlistView {
          id: watchlistView
          visible: !detailOpen && !root.settingsOpen && !root.searchOpen
          width: parent.width
          listName: watchlist.activeList
          pinnedKeys: watchlist.activePinnedSymbols
          editMode: root.editMode
          onRowRemoveRequested: function (key) { watchlist.removeSymbol(key) }
          onRowPinRequested: function (key) { watchlist.togglePin(key) }
          onRowMoveRequested: function (key, delta) { watchlist.moveSymbol(key, delta) }
          rows: root.quoteRows
          status: feed.status
          message: watchlist.error
          nowMs: root.nowMs
          textColor: root.foreground
          riseColor: palette.rise
          fallColor: palette.fall
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
        }

        SettingsView {
          visible: root.settingsOpen
          width: parent.width
          watchlist: watchlist
          textColor: root.foreground
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
        }

        SymbolDetail {
          id: detailView
          visible: !root.settingsOpen && watchlistView.detailOpen && watchlistView.selectedRow !== null
          width: parent.width
          row: watchlistView.selectedRow
          candleStore: candleStore
          nowMs: root.nowMs
          textColor: root.foreground
          riseColor: palette.rise
          fallColor: palette.fall
          mutedColor: root.muted
          panelFontFamily: root.fontFamily
          onDismissed: watchlistView.detailOpen = false
        }
      }
    }
  }
}
