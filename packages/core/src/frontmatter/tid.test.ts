import { describe, expect, test } from "bun:test"
import { generateTid, encodeBase32Sortable } from "./tid.js"

describe("encodeBase32Sortable", () => {
  test("encodes zero correctly", () => {
    expect(encodeBase32Sortable(0n, 4)).toBe("2222")
  })

  test("encodes small values", () => {
    expect(encodeBase32Sortable(31n, 2)).toBe("2z")
    expect(encodeBase32Sortable(32n, 2)).toBe("32")
  })

  test("produces correct length output", () => {
    expect(encodeBase32Sortable(12345n, 5).length).toBe(5)
    expect(encodeBase32Sortable(12345n, 11).length).toBe(11)
  })
})

describe("generateTid", () => {
  test("generates 13-character string", () => {
    const tid = generateTid()
    expect(tid.length).toBe(13)
  })

  test("uses only base32-sortable characters", () => {
    const tid = generateTid()
    expect(tid).toMatch(/^[234567abcdefghijklmnopqrstuvwxyz]+$/)
  })

  test("is deterministic with fixed timestamp and clockId", () => {
    const timestamp = new Date("2026-01-24T12:00:00.000Z")
    const tid1 = generateTid(timestamp, 0)
    const tid2 = generateTid(timestamp, 0)
    expect(tid1).toBe(tid2)
  })

  test("different clockIds produce different TIDs", () => {
    const timestamp = new Date("2026-01-24T12:00:00.000Z")
    const tid1 = generateTid(timestamp, 0)
    const tid2 = generateTid(timestamp, 1)
    expect(tid1).not.toBe(tid2)
    // Only last 2 chars should differ
    expect(tid1.slice(0, 11)).toBe(tid2.slice(0, 11))
  })

  test("alphabetically sortable = chronologically sorted", () => {
    const t1 = new Date("2020-01-01T00:00:00.000Z")
    const t2 = new Date("2025-06-15T12:30:00.000Z")
    const t3 = new Date("2026-01-24T23:59:59.999Z")

    const tid1 = generateTid(t1, 0)
    const tid2 = generateTid(t2, 0)
    const tid3 = generateTid(t3, 0)

    // Alphabetic comparison should match chronological order
    expect(tid1 < tid2).toBe(true)
    expect(tid2 < tid3).toBe(true)
    expect(tid1 < tid3).toBe(true)

    // Array sort should preserve chronological order
    const sorted = [tid3, tid1, tid2].sort()
    expect(sorted).toEqual([tid1, tid2, tid3])
  })

  test("TIDs from close timestamps are still sortable", () => {
    const t1 = new Date("2026-01-24T12:00:00.000Z")
    const t2 = new Date("2026-01-24T12:00:00.001Z") // 1ms later

    const tid1 = generateTid(t1, 0)
    const tid2 = generateTid(t2, 0)

    expect(tid1 < tid2).toBe(true)
  })
})
