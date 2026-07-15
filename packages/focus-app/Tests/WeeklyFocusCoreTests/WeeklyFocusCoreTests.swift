import XCTest
@testable import WeeklyFocusCore

final class WeeklyFocusCoreTests: XCTestCase {
    func testParsesWeeklyFocusSectionsWithFiveTodoCap() {
        let content = [
            "# Week",
            "",
            "## TODO",
            "- [x] Done",
            "- [ ] One",
            "- [ ] Two",
            "- [ ] Three",
            "- [ ] Four",
            "- [ ] Five",
            "- [ ] Six",
            "",
            "## Captured",
            "- [ ] 2026-07-07 20:34 Rough capture",
            "- [x] 2026-07-07 20:35 Done capture",
            "",
            "## Waiting",
            "- [ ] Waiting on review",
            "",
            "## Schedule",
            "- [ ] 0900 Scheduled item should not count"
        ].joined(separator: "\n")

        let snapshot = WeeklyFocusReader.parse(
            content,
            brainRoot: "/tmp/Brain",
            weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
            todoLimit: 5
        )

        XCTAssertEqual(snapshot.todos, ["One", "Two", "Three", "Four", "Five"])
        XCTAssertEqual(snapshot.overflowTodos, ["Six"])
        XCTAssertEqual(snapshot.now, "One")
        XCTAssertEqual(snapshot.next, "Two")
        XCTAssertEqual(snapshot.waiting, ["Waiting on review"])
        XCTAssertEqual(snapshot.capturedCount, 1)
    }

    func testParsesWeeklyFocusWithOverflowLimit() {
        let content = [
            "# Week",
            "",
            "## TODO",
            "- [ ] One",
            "- [ ] Two",
            "- [ ] Three",
            "- [ ] Four",
            "- [ ] Five",
            "- [ ] Six",
            "- [ ] Seven",
            "- [ ] Eight",
            "- [ ] Nine",
            "- [ ] Ten",
            "- [ ] Eleven",
            "",
            "## Captured"
        ].joined(separator: "\n")

        let snapshot = WeeklyFocusReader.parse(
            content,
            brainRoot: "/tmp/Brain",
            weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
            todoLimit: 5,
            overflowLimit: 5
        )

        XCTAssertEqual(snapshot.todos, ["One", "Two", "Three", "Four", "Five"])
        XCTAssertEqual(snapshot.overflowTodos, ["Six", "Seven", "Eight", "Nine", "Ten"])
    }

    func testFormatterPrintsSparseCard() {
        let snapshot = WeeklyFocusSnapshot(
            brainRoot: "/tmp/Brain",
            weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
            todos: ["One", "Two"],
            waiting: [],
            capturedCount: 1
        )

        XCTAssertEqual(
            WeeklyFocusFormatter.card(snapshot),
            [
                "Weekly Focus",
                "============",
                "",
                "Next items",
                "1. One",
                "2. Two",
                "",
                "Waiting",
                "- (none)",
                "",
                "Captured: 1 unchecked item",
                "",
                "Source: /tmp/Brain/Weekly Notes/Week of 2026-07-05.md"
            ].joined(separator: "\n")
        )
    }

    func testFindsBrainWikilinksInTodoText() {
        let links = BrainWikilinkResolver.wikilinks(
            in: "Review [[Daily Projects/2026-07-07/07 weekly note|the plan]] and [[Projects/foo]]"
        )

        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].target, "Daily Projects/2026-07-07/07 weekly note")
        XCTAssertEqual(links[0].displayText, "the plan")
        XCTAssertEqual(links[1].target, "Projects/foo")
        XCTAssertEqual(links[1].displayText, "Projects/foo")
    }

    func testResolvesPathWikilinkWithImplicitMarkdownExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let dailyDirectory = directory.appendingPathComponent("Daily Projects/2026-07-09", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dailyDirectory,
            withIntermediateDirectories: true
        )
        let note = dailyDirectory.appendingPathComponent("01 test note.md")
        try "hello".write(to: note, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            BrainWikilinkResolver.resolvePath(
                target: "Daily Projects/2026-07-09/01 test note",
                brainRoot: directory.path
            ),
            note.standardizedFileURL.path
        )
    }

    func testResolvesUIDWikilink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let projectDirectory = directory.appendingPathComponent("Projects/test", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        let note = projectDirectory.appendingPathComponent("executive summary.md")
        try [
            "---",
            "uid: 3mqexampletid",
            "type: project",
            "---",
            "",
            "# Test"
        ].joined(separator: "\n").write(to: note, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            BrainWikilinkResolver.resolvePath(
                target: "uid:3mqexampletid",
                brainRoot: directory.path
            ),
            note.standardizedFileURL.path
        )
    }

    func testRejectsWikilinkOutsideBrainRoot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        XCTAssertNil(
            BrainWikilinkResolver.resolvePath(
                target: "../outside",
                brainRoot: directory.path
            )
        )
    }

    func testBuildsCreateCommandWithoutInterpolatingTodoIntoShellCommand() {
        let todo = #"Fix $(touch /tmp/nope) and "quote" this"#
        let command = CmuxFocusLauncher.buildCommand(
            todo: todo,
            brainRoot: "/tmp/Brain",
            cmuxPath: "/bin/cmux"
        )

        XCTAssertEqual(command.executable, "/bin/cmux")
        XCTAssertEqual(command.arguments[0], "--json")
        XCTAssertEqual(command.arguments[1], "workspace")
        XCTAssertEqual(command.arguments[2], "create")
        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--cwd")! + 1], "/tmp/Brain")
        XCTAssertFalse(command.arguments.contains("--command"))
    }

    func testBuildsScriptedLaunchCommandWithoutInterpolatingTodoIntoShellCommand() throws {
        let todo = #"Fix $(touch /tmp/nope) and "quote" this"#
        let command = try CmuxFocusLauncher.buildScriptedCopilotCommand(todo: todo)

        XCTAssertTrue(command.contains("zsh -lic "))
        XCTAssertTrue(command.contains("source "))
        XCTAssertFalse(command.contains(todo))
    }

    func testBuildsCreateCommandWithFocusFlag() {
        let command = CmuxFocusLauncher.buildCommand(
            todo: "Self test",
            brainRoot: "/tmp/Brain",
            cmuxPath: "/bin/cmux",
            focus: false
        )

        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--focus")! + 1], "false")
    }

    func testLaunchCreatesWorkspaceWaitsForSurfaceSendsCommandAndSelects() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fakeCmux = directory.appendingPathComponent("cmux")
        let log = directory.appendingPathComponent("cmux.log")
        try [
            "#!/bin/sh",
            "printf '%s\\n' \"$*\" >> '\(log.path)'",
            "if [ \"$1\" = \"--json\" ] && [ \"$2\" = \"workspace\" ] && [ \"$3\" = \"create\" ]; then",
            "  echo '{\"workspace_ref\":\"workspace:999\",\"surface_ref\":\"surface:888\",\"window_ref\":\"window:1\"}'",
            "  exit 0",
            "fi",
            "if [ \"$1\" = \"read-screen\" ]; then",
            "  echo ready",
            "  exit 0",
            "fi",
            "if [ \"$1\" = \"send\" ]; then",
            "  exit 0",
            "fi",
            "if [ \"$1\" = \"workspace\" ] && [ \"$2\" = \"select\" ]; then",
            "  exit 0",
            "fi",
            "exit 1",
            ""
        ].joined(separator: "\n").write(to: fakeCmux, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCmux.path)

        let workspaceRef = try CmuxFocusLauncher.launch(
            todo: "Open focused workspace",
            brainRoot: "/tmp/Brain",
            cmuxPath: fakeCmux.path,
            commandOverride: "echo ok",
            focus: true
        )

        let calls = try String(contentsOf: log, encoding: .utf8)
        XCTAssertEqual(workspaceRef, "workspace:999")
        XCTAssertTrue(calls.contains("--json workspace create"))
        XCTAssertTrue(calls.contains("read-screen --workspace workspace:999 --surface surface:888"))
        XCTAssertTrue(calls.contains("send --workspace workspace:999 --surface surface:888 echo ok\\n"))
        XCTAssertTrue(calls.contains("workspace select workspace:999"))
    }

    func testLaunchDoesNotSwallowBrokenPipeWithoutWorkspaceRef() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fakeCmux = directory.appendingPathComponent("cmux")
        try [
            "#!/bin/sh",
            "if [ \"$1\" = \"--json\" ] && [ \"$2\" = \"workspace\" ] && [ \"$3\" = \"create\" ]; then",
            "  printf 'Failed to write to socket (Broken pipe, errno 32)\\n' >&2",
            "  exit 1",
            "fi",
            "exit 0",
            ""
        ].joined(separator: "\n").write(to: fakeCmux, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCmux.path)

        XCTAssertThrowsError(try CmuxFocusLauncher.launch(
            todo: "Broken pipe without workspace",
            brainRoot: "/tmp/Brain",
            cmuxPath: fakeCmux.path,
            commandOverride: "echo ok",
            focus: true
        ))
    }

    func testLaunchFailsWhenCmuxDoesNotReportWorkspaceRef() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fakeCmux = directory.appendingPathComponent("cmux")
        try [
            "#!/bin/sh",
            "if [ \"$1\" = \"--json\" ] && [ \"$2\" = \"workspace\" ] && [ \"$3\" = \"create\" ]; then",
            "  echo OK",
            "  exit 0",
            "fi",
            "exit 1",
            ""
        ].joined(separator: "\n").write(to: fakeCmux, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCmux.path)

        XCTAssertThrowsError(try CmuxFocusLauncher.launch(
            todo: "No workspace ref",
            brainRoot: "/tmp/Brain",
            cmuxPath: fakeCmux.path,
            commandOverride: "echo ok",
            focus: true
        ))
    }

    func testCmuxProcessEnvironmentRemovesInheritedCallerContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let environment = CmuxFocusLauncher.cmuxProcessEnvironment(
            [
                "HOME": directory.path,
                "USER": "jonmagic",
                "CMUX_WORKSPACE_ID": "old-workspace",
                "CMUX_SURFACE_ID": "old-surface",
                "CMUX_TAB_ID": "old-tab",
                "CMUX_SOCKET_PATH": "/tmp/inherited.sock",
                "CMUX_SOCKET": "",
                "CMUX_SOCKET_PASSWORD": "secret"
            ],
            homeDirectory: directory
        )

        XCTAssertNil(environment["CMUX_WORKSPACE_ID"])
        XCTAssertNil(environment["CMUX_SURFACE_ID"])
        XCTAssertNil(environment["CMUX_TAB_ID"])
        XCTAssertNil(environment["CMUX_SOCKET"])
        XCTAssertNil(environment["CMUX_SOCKET_PATH"])
        XCTAssertEqual(environment["CMUX_SOCKET_PASSWORD"], "secret")
        XCTAssertEqual(environment["HOME"], directory.path)
    }

    func testMarksSelectedTodoDoneInWeeklyNote() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let weeklyDirectory = directory.appendingPathComponent("Weekly Notes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: weeklyDirectory,
            withIntermediateDirectories: true
        )
        let weeklyNote = weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md")
        try [
            "# Week",
            "",
            "## TODO",
            "- [ ] One",
            "- [ ] Two",
            "",
            "## Schedule",
            "- [ ] Scheduled item",
            ""
        ].joined(separator: "\n").write(to: weeklyNote, atomically: true, encoding: .utf8)

        try WeeklyFocusReader.markTodoDone("Two", weeklyNotePath: weeklyNote.path)

        let updated = try String(contentsOf: weeklyNote, encoding: .utf8)
        XCTAssertTrue(updated.contains("- [ ] One"))
        XCTAssertTrue(updated.contains("- [x] Two"))
        XCTAssertTrue(updated.contains("- [ ] Scheduled item"))

        try FileManager.default.removeItem(at: directory)
    }

    func testAppendsTodoIntoTodoSection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let weeklyDirectory = directory.appendingPathComponent("Weekly Notes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: weeklyDirectory,
            withIntermediateDirectories: true
        )
        let weeklyNote = weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md")
        try [
            "# Week",
            "",
            "## TODO",
            "- [ ] One",
            "",
            "## Schedule",
            "- [ ] Scheduled item",
            ""
        ].joined(separator: "\n").write(to: weeklyNote, atomically: true, encoding: .utf8)

        let line = try WeeklyFocusReader.appendTodo("New TODO from field", weeklyNotePath: weeklyNote.path)

        let updated = try String(contentsOf: weeklyNote, encoding: .utf8)
        XCTAssertEqual(line, "- [ ] New TODO from field")
        XCTAssertLessThan(
            updated.range(of: "- [ ] New TODO from field")!.lowerBound,
            updated.range(of: "## Schedule")!.lowerBound
        )

        try FileManager.default.removeItem(at: directory)
    }

    func testAppendsCaptureAfterTodoSection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let weeklyDirectory = directory.appendingPathComponent("Weekly Notes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: weeklyDirectory,
            withIntermediateDirectories: true
        )
        let weeklyNote = weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md")
        try [
            "# Week",
            "",
            "## TODO",
            "- [ ] One",
            "",
            "## Schedule",
            "- [ ] Scheduled item",
            ""
        ].joined(separator: "\n").write(to: weeklyNote, atomically: true, encoding: .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 7,
            hour: 20,
            minute: 34
        ).date!

        let line = try WeeklyFocusReader.appendCapture(
            "Follow up from app",
            weeklyNotePath: weeklyNote.path,
            now: now,
            calendar: calendar
        )

        let updated = try String(contentsOf: weeklyNote, encoding: .utf8)
        XCTAssertEqual(line, "- [ ] 2026-07-07 20:34 Follow up from app")
        XCTAssertTrue(updated.contains("## Captured\n- [ ] 2026-07-07 20:34 Follow up from app"))
        XCTAssertLessThan(
            updated.range(of: "## Captured")!.lowerBound,
            updated.range(of: "## Schedule")!.lowerBound
        )

        try FileManager.default.removeItem(at: directory)
    }

    func testWeeklyNotePathUsesSundayWeekStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 7
        )
        let date = components.date!

        XCTAssertEqual(
            WeeklyFocusReader.weeklyNotePath(
                brainRoot: "/tmp/Brain",
                date: date,
                calendar: calendar
            ),
            "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md"
        )
    }

    func testReaderUsesCurrentWeekWhenItExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let weeklyDirectory = directory.appendingPathComponent("Weekly Notes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: weeklyDirectory,
            withIntermediateDirectories: true
        )
        try "# Current".write(
            to: weeklyDirectory.appendingPathComponent("Week of 2026-07-12.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Previous".write(
            to: weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md"),
            atomically: true,
            encoding: .utf8
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 12
        ).date!

        let reader = WeeklyFocusReader(
            brainRoot: directory.path,
            date: date,
            calendar: calendar
        )

        XCTAssertEqual(
            URL(fileURLWithPath: reader.weeklyNotePath).standardizedFileURL.path,
            weeklyDirectory.appendingPathComponent("Week of 2026-07-12.md").standardizedFileURL.path
        )
    }

    func testReaderFallsBackToLatestWeeklyNoteWhenCurrentWeekIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let weeklyDirectory = directory.appendingPathComponent("Weekly Notes", isDirectory: true)
        try FileManager.default.createDirectory(
            at: weeklyDirectory,
            withIntermediateDirectories: true
        )
        try "# Previous".write(
            to: weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Older".write(
            to: weeklyDirectory.appendingPathComponent("Week of 2026-06-28.md"),
            atomically: true,
            encoding: .utf8
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 12
        ).date!

        let reader = WeeklyFocusReader(
            brainRoot: directory.path,
            date: date,
            calendar: calendar
        )

        XCTAssertEqual(
            URL(fileURLWithPath: reader.weeklyNotePath).standardizedFileURL.path,
            weeklyDirectory.appendingPathComponent("Week of 2026-07-05.md").standardizedFileURL.path
        )
    }
}
