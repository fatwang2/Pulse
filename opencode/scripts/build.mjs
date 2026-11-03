// Compiles src/ to dist/: the TSX with Solid's universal transform for OpenTUI,
// as opencode itself does for local plugins. opencode v2 does not transform
// files under node_modules, so the npm package ships this compiled JavaScript.
// solid-js and @opentui/solid stay imports; opencode provides its own copies.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import path from "node:path"
import { transformAsync } from "@babel/core"
import solid from "babel-preset-solid"
import typescript from "@babel/preset-typescript"

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const src = path.join(root, "src")
const dist = path.join(root, "dist")
rmSync(dist, { recursive: true, force: true })
mkdirSync(dist)

// "./view.tsx" becomes "./view.js" in the compiled files.
const relink = (code) => code.replace(/(from\s+["']\.\/[\w-]+)\.tsx(["'])/g, "$1.js$2")

for (const name of readdirSync(src).sort()) {
  const file = path.join(src, name)
  const text = readFileSync(file, "utf8")
  if (name.endsWith(".tsx")) {
    const result = await transformAsync(text, {
      filename: file,
      configFile: false,
      babelrc: false,
      presets: [
        [solid, { moduleName: "@opentui/solid", generate: "universal" }],
        [typescript, { isTSX: true, allExtensions: true, onlyRemoveTypeImports: false }],
      ],
    })
    writeFileSync(path.join(dist, name.replace(/\.tsx$/, ".js")), relink(result.code) + "\n")
  } else if (name.endsWith(".js")) {
    writeFileSync(path.join(dist, name), text)
  }
}
console.log(`Built ${readdirSync(dist).length} files into dist/`)
