// Wikilinks module exports
export {
  WIKILINK_REGEX,
  UID_PREFIX,
  parseWikilink,
  formatWikilink,
  extractWikilinks,
  pathToDisplayPath,
  type ParsedWikilink,
} from "./patterns.js"

export {
  buildUidIndex,
  getPathByUid,
  getUidByPath,
  type UidIndex,
  type FileInfo,
} from "./uidIndex.js"

export { resolveWikilink } from "./resolve.js"
