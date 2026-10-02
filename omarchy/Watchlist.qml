import QtQuick
import Quickshell
import Quickshell.Io
import "Config.js" as Config

// The watchlist store, backed by `~/.config/omarchy/pulse/watchlist.json`.
//
// All shape and arithmetic lives in Config.js, where it is tested; this file
// owns exactly the two things QML has to own — the FileView and the property
// notifications. Omarchy configures through files, so the file is the source
// of truth and the panel is one of two editors for it. `watchChanges` keeps
// both honest: an edit from either side lands without restarting the shell.
QtObject {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/pulse"
  readonly property string configPath: configDir + "/watchlist.json"

  property var config: Config.emptyConfig()
  property string error: ""
  property bool loaded: false

  // Derived views the panel binds to. Recomputed once per config change, not
  // per delegate.
  readonly property var listNames: Config.listNames(config)
  readonly property string activeList: config.activeList
  readonly property var activeSymbols: Config.activeSymbols(config)
  readonly property var activePinnedSymbols: Config.activePinnedSymbols(config)
  readonly property var recentSearches: config.recentSearches || []
  readonly property bool prioritizeOpenMarkets: config.prioritizeOpenMarkets !== false
  readonly property var allSymbols: Config.allSymbols(config)
  readonly property int pollIntervalSeconds: config.pollIntervalSeconds
  readonly property string barDisplay: config.barDisplay
  readonly property string pinnedSymbol: config.pinnedSymbol
  readonly property int carouselIntervalSeconds: config.carouselIntervalSeconds

  function canonical(raw) { return Config.canonical(raw) }
  function contains(raw) { return Config.contains(root.config, raw) }
  function isPinned(raw) { return Config.isPinned(root.config, raw) }

  function load(raw) {
    try {
      root.config = Config.parse(raw)
    } catch (e) {
      // A half-saved file is a normal state to observe with watchChanges on,
      // so the previous config is kept rather than blanked; the panel says why.
      root.error = "watchlist.json: " + e.message
      return
    }
    root.error = ""
    root.loaded = true
  }

  // Applies a Config.js operation and persists the result. Operations return
  // the same object when they refuse an edit, and a refused edit is not a
  // write. Nothing writes before the first successful read — that is what
  // stops a transient parse failure from being persisted as an empty file.
  function apply(next) {
    if (!root.loaded || next === root.config) return false
    root.config = next
    file.setText(Config.serialize(next))
    return true
  }

  function addSymbol(raw) { return apply(Config.addSymbol(root.config, raw)) }
  function removeSymbol(raw) { return apply(Config.removeSymbol(root.config, raw)) }
  function moveSymbol(raw, delta) { return apply(Config.moveSymbol(root.config, raw, delta)) }
  function togglePin(raw) { return apply(Config.togglePin(root.config, raw)) }
  function recordRecentSearch(query) { return apply(Config.recordRecentSearch(root.config, query)) }
  function clearRecentSearches() { return apply(Config.clearRecentSearches(root.config)) }
  function selectList(name) { return apply(Config.selectList(root.config, name)) }
  function addList(name) { return apply(Config.addList(root.config, name)) }
  function renameList(from, to) { return apply(Config.renameList(root.config, from, to)) }
  function removeList(name) { return apply(Config.removeList(root.config, name)) }
  function setValue(key, value) { return apply(Config.setValue(root.config, key, value)) }

  property FileView file: FileView {
    id: file
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onFileChanged: reload()
    onLoadFailed: {
      root.error = ""
      root.config = Config.emptyConfig()
      root.loaded = true
    }
  }
}
