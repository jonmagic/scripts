import { Form, ActionPanel, Action, showToast, Toast } from "@raycast/api"
import { useState } from "react"

import { addBrainTask } from "@jonmagic/scripts-core"

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
                const addOptions: Parameters<typeof addBrainTask>[0] = {
                  title: text,
                }
                if (source.trim()) {
                  addOptions.source = source
                }

                const result = await addBrainTask(addOptions)
                await showToast({
                  style: Toast.Style.Success,
                  title: "Added to Brain Tasks",
                  message: result.title,
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
        title="Task"
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
