// Loads a QML JavaScript resource under Node.
//
// QML resources declare their dependencies with `.import`, which the QML engine
// understands and Node does not — it is not JavaScript. Rather than keep two
// copies of every module, or make the modules dependency-free by duplicating
// what they share, the tests translate those lines into requires and run the
// same file the shell runs. If this shim ever diverges from what QML does, the
// tests are testing the wrong thing, so it stays deliberately literal: strip
// `.pragma`, rewrite `.import`, change nothing else.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const root = path.resolve(__dirname, "..")
const cache = new Map()

function translate(source) {
  return source
    .replace(/^\.pragma\s+\w+\s*$/gm, "")
    .replace(
      /^\.import\s+"([^"]+)"\s+as\s+([A-Za-z_$][\w$]*)\s*$/gm,
      (match, dependency, alias) => `const ${alias} = __load(${JSON.stringify(dependency)});`
    )
}

function load(relativePath) {
  const filename = path.resolve(root, relativePath)
  if (cache.has(filename)) return cache.get(filename)

  const module = { exports: {} }
  const compiled = vm.compileFunction(
    translate(fs.readFileSync(filename, "utf8")),
    ["module", "exports", "__load"],
    { filename }
  )
  compiled(module, module.exports, (dependency) =>
    load(path.join(path.dirname(relativePath), dependency))
  )

  cache.set(filename, module.exports)
  return module.exports
}

module.exports = { load }
