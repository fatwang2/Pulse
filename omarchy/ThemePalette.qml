import QtQuick
import Quickshell
import Quickshell.Io

// Rise and fall colors, read from the active Omarchy theme.
//
// The shell's public `Color` singleton exposes red as `urgent` but has no green
// role at all, so a market panel has nowhere to ask for the other half of the
// pair. This reads the same `colors.toml` the theme ships and takes its ANSI
// green and red, which keeps the panel inside the theme instead of inventing
// two hex values that clash with every palette but one.
QtObject {
  id: root

  required property color fallbackRise
  required property color fallbackFall

  property color parsedRise: fallbackRise
  property color parsedFall: fallbackFall

  readonly property color rise: parsedRise
  readonly property color fall: parsedFall

  function paletteColor(raw, role, fallback) {
    var pattern = new RegExp("^\\s*" + role + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m")
    var match = String(raw || "").match(pattern)
    return match ? match[1] : fallback
  }

  function load(raw) {
    parsedRise = paletteColor(raw, "green", fallbackRise)
    parsedFall = paletteColor(raw, "red", fallbackFall)
  }

  onFallbackRiseChanged: colorsFile.reload()
  onFallbackFallChanged: colorsFile.reload()

  property FileView colorsFile: FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    onFileChanged: reload()
    onLoadFailed: root.load("")
  }
}
