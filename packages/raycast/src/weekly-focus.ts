import { closeMainWindow, showToast, Toast } from "@raycast/api"
import { execFile } from "node:child_process"
import * as os from "node:os"
import * as path from "node:path"

function weeklyFocusAppScript(): string {
  return (
    process.env.WEEKLY_FOCUS_APP ??
    path.join(os.homedir(), "code", "jonmagic", "scripts", "bin", "weekly-focus-app")
  )
}

async function launchWeeklyFocusApp(): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    execFile(weeklyFocusAppScript(), [], (error, _stdout, stderr) => {
      if (error) {
        const message = stderr.trim() || error.message
        reject(new Error(message))
        return
      }

      resolve()
    })
  })
}

export default async function Command() {
  try {
    await launchWeeklyFocusApp()
    await showToast({
      style: Toast.Style.Success,
      title: "Opened Weekly Focus",
    })
    await closeMainWindow({ clearRootSearch: true })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    await showToast({
      style: Toast.Style.Failure,
      title: "Failed to open Weekly Focus",
      message,
    })
  }
}
