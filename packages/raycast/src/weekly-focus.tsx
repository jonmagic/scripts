import {
  Action,
  ActionPanel,
  closeMainWindow,
  List,
  showToast,
  Toast,
} from "@raycast/api"
import { useEffect, useState } from "react"

import {
  launchFocusCard,
  launchWeeklyTodo,
  runWeeklyFocus,
} from "@jonmagic/scripts-cli"
import type { WeeklyNoteFocus } from "@jonmagic/scripts-core"

interface FocusState {
  error?: string
  focus?: WeeklyNoteFocus
  loading: boolean
}

async function showFailure(title: string, error: unknown): Promise<void> {
  const message = error instanceof Error ? error.message : String(error)
  await showToast({
    style: Toast.Style.Failure,
    title,
    message,
  })
}

export default function Command() {
  const [state, setState] = useState<FocusState>({ loading: true })

  async function refresh(): Promise<void> {
    setState({ loading: true })
    try {
      const focus = await runWeeklyFocus({ todoLimit: 5 })
      setState({ focus, loading: false })
    } catch (error) {
      setState({
        error: error instanceof Error ? error.message : String(error),
        loading: false,
      })
    }
  }

  useEffect(() => {
    void refresh()
  }, [])

  async function workTodo(todo: string): Promise<void> {
    try {
      if (!state.focus) {
        return
      }

      await launchWeeklyTodo({ brainRoot: state.focus.brainRoot, todo })
      await showToast({
        style: Toast.Style.Success,
        title: "Opened Copilot workspace",
        message: todo,
      })
      await closeMainWindow({ clearRootSearch: true })
    } catch (error) {
      await showFailure("Failed to open Copilot workspace", error)
    }
  }

  async function openFocusCard(): Promise<void> {
    try {
      if (!state.focus) {
        return
      }

      await launchFocusCard({ brainRoot: state.focus.brainRoot })
      await showToast({
        style: Toast.Style.Success,
        title: "Opened Weekly Focus",
      })
      await closeMainWindow({ clearRootSearch: true })
    } catch (error) {
      await showFailure("Failed to open Weekly Focus", error)
    }
  }

  const focus = state.focus
  const todos = focus?.todos ?? []
  const waiting = focus?.waiting ?? []

  return (
    <List
      isLoading={state.loading}
      searchBarPlaceholder="Weekly Focus shows at most five next TODOs"
    >
      {state.error ? (
        <List.EmptyView title="Could not load Weekly Focus" description={state.error} />
      ) : null}
      {!state.error && !state.loading && todos.length === 0 ? (
        <List.EmptyView title="No unchecked TODOs in this week's note" />
      ) : null}
      {todos.map((todo, index) => (
        <List.Item
          key={`${index}-${todo}`}
          title={todo}
          subtitle={`TODO ${index + 1} of ${todos.length}`}
          accessories={[
            {
              text:
                index === 0 ? "Now" : index === 1 ? "Next" : `#${index + 1}`,
            },
          ]}
          actions={
            <ActionPanel>
              <Action
                title="Work This TODO in Copilot"
                onAction={() => {
                  void workTodo(todo)
                }}
              />
              <Action
                title="Open Full-Screen Focus in cmux"
                onAction={() => {
                  void openFocusCard()
                }}
              />
              <Action
                title="Refresh"
                shortcut={{ modifiers: ["cmd"], key: "r" }}
                onAction={() => {
                  void refresh()
                }}
              />
              <Action.CopyToClipboard title="Copy TODO" content={todo} />
            </ActionPanel>
          }
        />
      ))}
      {waiting.length > 0 ? (
        <List.Section title="Waiting">
          {waiting.map((item, index) => (
            <List.Item
              key={`waiting-${index}-${item}`}
              title={item}
              accessories={[{ text: "Waiting" }]}
            />
          ))}
        </List.Section>
      ) : null}
      {focus ? (
        <List.Section title="Weekly Note">
          <List.Item
            title={`${focus.capturedCount} unchecked captured ${
              focus.capturedCount === 1 ? "item" : "items"
            }`}
            subtitle={focus.weeklyNotePath}
            actions={
              <ActionPanel>
                <Action
                  title="Open Full-Screen Focus in cmux"
                  onAction={() => {
                    void openFocusCard()
                  }}
                />
                <Action
                  title="Refresh"
                  shortcut={{ modifiers: ["cmd"], key: "r" }}
                  onAction={() => {
                    void refresh()
                  }}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      ) : null}
    </List>
  )
}
