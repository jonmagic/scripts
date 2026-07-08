import { Form, ActionPanel, Action, showToast, Toast } from "@raycast/api"
import { useState } from "react"

import { appendWeeklyNoteCapture } from "@jonmagic/scripts-core"

export default function Command() {
  const [text, setText] = useState("")
  const [source, setSource] = useState("")

  return (
    <Form
      actions={
        <ActionPanel>
          <Action
            title="Capture"
            onAction={async () => {
              if (!text.trim()) {
                return
              }

              try {
                const captureOptions: Parameters<typeof appendWeeklyNoteCapture>[0] = {
                  text,
                }
                if (source.trim()) {
                  captureOptions.source = source
                }

                const result = await appendWeeklyNoteCapture(captureOptions)
                await showToast({
                  style: Toast.Style.Success,
                  title: "Captured to Weekly Note",
                  message: result.line,
                })
                setText("")
                setSource("")
              } catch (err) {
                const message = err instanceof Error ? err.message : String(err)
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to capture",
                  message,
                })
              }
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="text"
        title="Capture"
        placeholder="Follow up with @handle about the review ask"
        value={text}
        onChange={setText}
      />
      <Form.TextField
        id="source"
        title="Source"
        placeholder="Slack thread, meeting note, PR URL, or leave blank"
        value={source}
        onChange={setSource}
      />
    </Form>
  )
}
