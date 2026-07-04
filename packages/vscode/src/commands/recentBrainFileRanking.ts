export interface RecentBrainFileCandidate {
  absolutePath: string
  relativePath: string
  mtime: number
}

export interface RankedRecentBrainFile extends RecentBrainFileCandidate {
  gitStatus: string | null
}

export function rankRecentBrainFiles(
  files: RecentBrainFileCandidate[],
  gitStatuses: Map<string, string>,
  limit: number
): RankedRecentBrainFile[] {
  return files
    .map((file) => ({
      ...file,
      gitStatus: gitStatuses.get(file.relativePath) ?? null,
    }))
    .sort((left, right) => {
      const leftModified = left.gitStatus !== null
      const rightModified = right.gitStatus !== null

      if (leftModified !== rightModified) {
        return leftModified ? -1 : 1
      }

      if (right.mtime !== left.mtime) {
        return right.mtime - left.mtime
      }

      return left.relativePath.localeCompare(right.relativePath)
    })
    .slice(0, limit)
}
