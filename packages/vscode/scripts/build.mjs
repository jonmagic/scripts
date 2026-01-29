import esbuild from "esbuild"
import { execSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import path from "node:path"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const watch = process.argv.includes("--watch")

const coreDir = path.join(__dirname, "../../core")

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
  execSync("bun run build", { cwd: coreDir, stdio: "inherit" })
  const ctx = await esbuild.context(options)
  await ctx.watch()
  console.log("Watching…")
} else {
  execSync("bun run build", { cwd: coreDir, stdio: "inherit" })
  await esbuild.build(options)
}
