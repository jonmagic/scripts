import { createDailyProjectNote } from "@jonmagic/scripts-core"

export type CreateDailyProjectNoteCliOptions = {
  title: string
  brainRoot?: string
  updateWeeklyNote?: boolean
  weeklyNotePath?: string
}

export async function runCreateDailyProjectNote(
  options: CreateDailyProjectNoteCliOptions
): Promise<ReturnType<typeof createDailyProjectNote>> {
  const result = await createDailyProjectNote({
    title: options.title,
    brainRoot: options.brainRoot,
    updateWeeklyNote: options.updateWeeklyNote,
    weeklyNotePath: options.weeklyNotePath,
  })

  return result
}
