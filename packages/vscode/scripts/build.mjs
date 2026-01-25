import esbuild from "esbuild"
import { fileURLToPath } from "node:url"
import path from "node:path"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const watch = process.argv.includes("--watch")

/** @type {import('esbuild').BuildOptions} */
const options = {
  entryPoints: [path.join(__dirname, "../src/extension.ts")],
  bundle: true,
  platform: "node",
  format: "cjs",
  target: "node18",
  outfile: path.join(__dirname, "../dist/extension.js"),
  sourcemap: true,
  external: ["vscode"],
  logLevel: "info"
}

if (watch) {
  const ctx = await esbuild.context(options)
  await ctx.watch()
  // eslint-disable-next-line no-console
  console.log("Watching…")
} else {
  await esbuild.build(options)
}
