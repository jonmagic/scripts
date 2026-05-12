// TID (Timestamp ID) generation following AT Protocol specification.
// TIDs are sortable, timestamp-based identifiers.
//
// Format: 13 characters, base32-sortable encoding
// - First 11 chars: microseconds since Unix epoch (53 bits)
// - Last 2 chars: clock ID (10 bits) for collision avoidance

// Base32-sortable alphabet (same as AT Protocol)
// Chosen so alphabetic sort = numeric sort
const BASE32_SORTABLE = "234567abcdefghijklmnopqrstuvwxyz"

/**
 * Encode a bigint value to base32-sortable string of specified length.
 */
export function encodeBase32Sortable(value: bigint, length: number): string {
  let result = ""
  let v = value
  for (let i = 0; i < length; i++) {
    result = BASE32_SORTABLE[Number(v & 0x1fn)] + result
    v >>= 5n
  }
  return result
}

/**
 * Generate a TID (Timestamp ID) for use as a unique identifier.
 *
 * @param timestamp - Optional timestamp to use (defaults to now)
 * @param clockId - Optional clock ID for testing (defaults to random 0-1023)
 * @returns 13-character base32-sortable string
 */
export function generateTid(
  timestamp?: Date,
  clockId?: number
): string {
  const ts = timestamp ?? new Date()

  // Microseconds since Unix epoch (53 bits max)
  const micros = BigInt(Math.floor(ts.getTime() * 1000))

  // Clock ID: random 10-bit value for collision avoidance
  const clock = clockId ?? Math.floor(Math.random() * 1024)

  // Encode timestamp (11 chars = 55 bits, we use 53)
  const timestampEncoded = encodeBase32Sortable(micros, 11)

  // Encode clock ID (2 chars = 10 bits)
  const clockEncoded = encodeBase32Sortable(BigInt(clock), 2)

  return timestampEncoded + clockEncoded
}

/**
 * Produce a stable 10-bit clock ID from a seed, usually a relative file path.
 */
export function clockIdForSeed(seed: string): number {
  let hash = 0x811c9dc5

  for (let i = 0; i < seed.length; i++) {
    hash ^= seed.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }

  return (hash >>> 0) & 0x3ff
}

/**
 * Generate a TID that does not collide with existing UIDs.
 *
 * When many notes share a path-derived created timestamp, a plain random
 * 10-bit clock ID is collision-prone. This walks the clock space
 * deterministically, then advances the timestamp by milliseconds if needed.
 */
export function generateUniqueTid(
  existingUids: Iterable<string>,
  timestamp?: Date,
  seed = ""
): string {
  const existing = existingUids instanceof Set
    ? existingUids
    : new Set(existingUids)
  const baseTimestamp = timestamp ?? new Date()
  const initialClockId = seed
    ? clockIdForSeed(seed)
    : Math.floor(Math.random() * 1024)

  for (let attempt = 0; ; attempt++) {
    const timestampOffsetMs = Math.floor(attempt / 1024)
    const clockId = (initialClockId + attempt) % 1024
    const candidate = generateTid(
      new Date(baseTimestamp.getTime() + timestampOffsetMs),
      clockId
    )

    if (!existing.has(candidate)) {
      return candidate
    }
  }
}
