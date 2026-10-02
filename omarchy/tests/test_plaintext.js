const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

// Marketplace review finding: QML Text defaults to AutoText, which sniffs
// rich-text markup — so a crafted quote name from the network could parse as
// markup inside the long-lived shell process. Every Text whose `text:` binds
// a dynamic expression must therefore force PlainText. This walks each QML
// file's Text blocks and fails on any dynamic binding without it.

const root = path.resolve(__dirname, "..")
const files = ["Panel.qml", ...fs.readdirSync(path.join(root, "components"))
  .filter(f => f.endsWith(".qml")).map(f => "components/" + f)]

// A binding is dynamic when it references anything beyond string literals —
// identifiers reached through these roots carry network or config data.
const DYNAMIC = /\b(root|modelData|parent|chip|tab|resultRow|listRow|sourceRow|watchlist|search|quote|Model|SymbolID|Market)\b/

function textBlocks(source) {
  const blocks = []
  const opener = /(^|\n)(\s*)Text\s*\{/g
  let match
  while ((match = opener.exec(source)) !== null) {
    let depth = 1
    let i = opener.lastIndex
    while (i < source.length && depth > 0) {
      if (source[i] === "{") depth++
      else if (source[i] === "}") depth--
      i++
    }
    blocks.push(source.slice(opener.lastIndex, i))
  }
  return blocks
}

for (const file of files) {
  test(`dynamic Text bindings render as plain text in ${file}`, () => {
    const source = fs.readFileSync(path.join(root, file), "utf8")
    for (const block of textBlocks(source)) {
      // Only the block's own text binding, not nested children's.
      const own = block.split(/\n\s*(?:Text|HoverHandler|TapHandler|PanelToolTip|PlainToolTip)\s*\{/)[0]
      const binding = own.match(/(^|\n)\s*text:\s*(.+)/)
      if (!binding) continue
      const expression = binding[2]
      if (!DYNAMIC.test(expression)) continue
      assert.ok(/textFormat:\s*Text\.PlainText/.test(own),
        `Text with dynamic binding lacks textFormat: Text.PlainText — text: ${expression.trim()}`)
      // A textFormat line jammed inside a multiline binding truncates the
      // expression — the header once rendered "true" this way. The line
      // after textFormat must start a new property, never a continuation.
      const jammed = own.match(/textFormat:\s*Text\.PlainText\s*\n\s*[?:.]/)
      assert.ok(!jammed,
        `textFormat splits a multiline binding — text: ${expression.trim()}`)
    }
  })
}
