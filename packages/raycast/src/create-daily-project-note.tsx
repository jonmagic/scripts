import { Form, ActionPanel, Action, showToast, Toast, open } from "@raycast/api"
import { useState } from "react"

import { createDailyProjectNote } from "@jonmagic/scripts-core"

export default function Command() {
  const [title, setTitle] = useState("")

  return (
    <Form
      actions={
        <ActionPanel>
          <Action
            title="Create"
            onAction={async () => {
              if (!title.trim()) {
                return
              }
              try {
                const result = await createDailyProjectNote({ title })
                await showToast({
                  style: Toast.Style.Success,
                  title: "Created Daily Project Note",
                  message: result.filePath
                })
                await open(result.filePath)
              } catch (err) {
                const message = err instanceof Error ? err.message : String(err)
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to create note",
                  message
                })
              }
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="title"
        title="Title"
        placeholder="refactor stale queue cleanup"
        value={title}
        onChange={setTitle}
      />
    </Form>
  )
}
