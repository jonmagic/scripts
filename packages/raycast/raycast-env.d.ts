/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `create-daily-project-note` command */
  export type CreateDailyProjectNote = ExtensionPreferences & {}
  /** Preferences accessible in the `capture-weekly-note` command */
  export type CaptureWeeklyNote = ExtensionPreferences & {}
  /** Preferences accessible in the `weekly-focus` command */
  export type WeeklyFocus = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `create-daily-project-note` command */
  export type CreateDailyProjectNote = {}
  /** Arguments passed to the `capture-weekly-note` command */
  export type CaptureWeeklyNote = {}
  /** Arguments passed to the `weekly-focus` command */
  export type WeeklyFocus = {}
}

