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
  const createOptions: Parameters<typeof createDailyProjectNote>[0] = {
    title: options.title,
  }
  if (options.brainRoot !== undefined) {
    createOptions.brainRoot = options.brainRoot
  }
  if (options.updateWeeklyNote !== undefined) {
    createOptions.updateWeeklyNote = options.updateWeeklyNote
  }
  if (options.weeklyNotePath !== undefined) {
    createOptions.weeklyNotePath = options.weeklyNotePath
  }

  const result = await createDailyProjectNote(createOptions)

  return result
}
