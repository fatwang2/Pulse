import QtQuick
import "YahooAdapter.js" as Yahoo

// Symbol lookup for the settings view.
//
// Typing is throttled rather than sent per keystroke: Yahoo rate-limits per IP
// and the same budget pays for the quotes on screen. A request already in
// flight is superseded rather than cancelled, and a late response for an older
// query is dropped — otherwise a fast typist sees results for a prefix they
// have already finished typing.
QtObject {
  id: root

  property string query: ""
  property var results: []
  property bool searching: false
  property string message: ""

  property string _pendingQuery: ""
  property string _servedQuery: ""

  function clear() {
    root.query = ""
    root.results = []
    root.searching = false
    root.message = ""
    debounce.stop()
  }

  function _run(text) {
    var spec = Yahoo.searchRequest(text)
    if (!spec) {
      root.results = []
      root.searching = false
      root.message = ""
      return
    }

    root.searching = true
    root._pendingQuery = spec.query

    var xhr = new XMLHttpRequest()
    xhr.open("GET", spec.url)
    xhr.timeout = 8000
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) Pulse/0.1 (+https://www.pulseticker.app)")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      // A response for a query the user has moved past is not an answer.
      if (spec.query !== root._pendingQuery) return
      root.searching = false
      root._servedQuery = spec.query

      if (xhr.status === 400) {
        // Yahoo answers 400 to queries its index cannot parse, which includes
        // Chinese, Japanese and Korean text. That is an empty result, not a
        // fault: those markets are reached by code until a native-language
        // index is wired.
        // Yahoo's index cannot parse this, but a code the user typed still
        // resolves locally — which is exactly the fallback the message names.
        root.results = Yahoo.parseSearch(null, spec.query)
        root.message = root.results.length > 0
          ? ""
          : "Yahoo indexes English names and tickers. Try a code, like 600519.SH."
        return
      }
      if (xhr.status === 429) {
        root.results = Yahoo.parseSearch(null, spec.query)
        root.message = "Rate limited. Try again in a moment."
        return
      }
      if (xhr.status < 200 || xhr.status >= 300) {
        root.results = Yahoo.parseSearch(null, spec.query)
        root.message = xhr.status === 0 ? "Offline." : ("Search failed (HTTP " + xhr.status + ").")
        return
      }

      var parsed = []
      try {
        parsed = Yahoo.parseSearch(JSON.parse(xhr.responseText), spec.query)
      } catch (e) {
        parsed = Yahoo.parseSearch(null, spec.query)
      }
      root.results = parsed
      root.message = parsed.length === 0 ? "Nothing found for “" + spec.query + "”." : ""
    }
    xhr.send()
  }

  onQueryChanged: {
    var text = String(root.query || "").replace(/^\s+|\s+$/g, "")
    if (!text) {
      root.results = []
      root.searching = false
      root.message = ""
      debounce.stop()
      return
    }
    if (text === root._servedQuery) return
    debounce.restart()
  }

  property Timer debounce: Timer {
    id: debounce
    interval: 350
    repeat: false
    onTriggered: root._run(root.query)
  }
}
