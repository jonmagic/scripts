/// <reference types="bun-types" />

import { describe, expect, test } from "bun:test"

import {
  buildAddBrainTaskArgs,
  buildListBrainTasksArgs,
} from "./brainTasks.js"

describe("brain tasks board actions", () => {
  test("adds tasks into the current week so Weekly Focus can see them", () => {
    // Weekly Focus queries the board with week:@current. A task with no week
    // is invisible there until the next weekly roll.
    expect(buildAddBrainTaskArgs({ title: "Ship the current PR" })).toEqual([
      "add",
      "--title",
      "Ship the current PR",
      "--status",
      "Todo",
      "--week",
      "current",
      "--json",
    ])
  })

  test("passes optional metadata through and trims it", () => {
    expect(
      buildAddBrainTaskArgs({
        title: "  Follow up on the review ask  ",
        status: "Doing",
        week: "previous",
        source: " Slack thread ",
        area: "tech-debt",
        target: "",
      })
    ).toEqual([
      "add",
      "--title",
      "Follow up on the review ask",
      "--status",
      "Doing",
      "--week",
      "previous",
      "--json",
      "--source",
      "Slack thread",
      "--area",
      "tech-debt",
    ])
  })

  test("rejects blank titles before shelling out", () => {
    expect(() => buildAddBrainTaskArgs({ title: "   " })).toThrow(
      "Task title is required"
    )
  })

  test("lists the current week as JSON by default", () => {
    expect(buildListBrainTasksArgs()).toEqual([
      "list",
      "--week",
      "current",
      "--json",
    ])
  })

  test("supports status filters and the focus flag", () => {
    expect(
      buildListBrainTasksArgs({
        week: "all",
        status: "Todo,Doing",
        focusOnly: true,
      })
    ).toEqual([
      "list",
      "--week",
      "all",
      "--json",
      "--status",
      "Todo,Doing",
      "--focus",
    ])
  })
})
