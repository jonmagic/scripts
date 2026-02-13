/// <reference types="bun-types" />

import { describe, expect, test } from "bun:test"

import { detectTool, buildResumeCommand } from "./detectSession.js"

describe("detectTool", () => {
  test("returns opencode when OPENCODE=1", () => {
    const orig = process.env.OPENCODE
    process.env.OPENCODE = "1"
    try {
      expect(detectTool()).toBe("opencode")
    } finally {
      if (orig !== undefined) {
        process.env.OPENCODE = orig
      } else {
        delete process.env.OPENCODE
      }
    }
  })

  test("returns null when no agent env vars set", () => {
    const origOpencode = process.env.OPENCODE
    const origCopilot = process.env.COPILOT_PROXY_TOKEN_CMD
    const origClaude = process.env.CLAUDE_CODE

    delete process.env.OPENCODE
    delete process.env.COPILOT_PROXY_TOKEN_CMD
    delete process.env.CLAUDE_CODE
    delete process.env.CLAUDE

    try {
      expect(detectTool()).toBeNull()
    } finally {
      if (origOpencode !== undefined) process.env.OPENCODE = origOpencode
      if (origCopilot !== undefined)
        process.env.COPILOT_PROXY_TOKEN_CMD = origCopilot
      if (origClaude !== undefined) process.env.CLAUDE_CODE = origClaude
    }
  })
})

describe("buildResumeCommand", () => {
  test("opencode format", () => {
    expect(buildResumeCommand("opencode", "ses_abc123")).toBe(
      "opencode -s ses_abc123"
    )
  })

  test("copilot format", () => {
    expect(
      buildResumeCommand(
        "copilot",
        "38ec825d-c565-4793-8d42-122833c7be0e"
      )
    ).toBe("copilot --resume=38ec825d-c565-4793-8d42-122833c7be0e")
  })

  test("claude format", () => {
    expect(
      buildResumeCommand(
        "claude",
        "38ec825d-c565-4793-8d42-122833c7be0e"
      )
    ).toBe("claude --resume 38ec825d-c565-4793-8d42-122833c7be0e")
  })
})
