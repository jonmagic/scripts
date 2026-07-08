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

    func testBuildsLaunchCommandWithoutInterpolatingTodoIntoShellCommand() {
        let todo = #"Fix $(touch /tmp/nope) and "quote" this"#
        let command = CmuxFocusLauncher.buildCommand(
            todo: todo,
            brainRoot: "/tmp/Brain",
            cmuxPath: "/bin/cmux"
        )

        XCTAssertEqual(command.executable, "/bin/cmux")
        XCTAssertEqual(command.arguments[0], "workspace")
        XCTAssertEqual(command.arguments[1], "create")
        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--cwd")! + 1], "/tmp/Brain")
        XCTAssertEqual(
            command.arguments[command.arguments.firstIndex(of: "--command")! + 1],
            #"zsh -lic 'source "$WEEKLY_FOCUS_SCRIPT"'"#
        )
        XCTAssertFalse(command.arguments[command.arguments.firstIndex(of: "--command")! + 1].contains(todo))
    }

    func testBuildsScriptedLaunchCommandWithoutInterpolatingTodoIntoShellCommand() throws {
        let todo = #"Fix $(touch /tmp/nope) and "quote" this"#
        let command = try CmuxFocusLauncher.buildScriptedCopilotCommand(todo: todo)

        XCTAssertTrue(command.contains("zsh -lic "))
        XCTAssertFalse(command.contains(todo))
    }

    func testBuildsLaunchCommandWithSelfTestOverride() {
        let command = CmuxFocusLauncher.buildCommand(
            todo: "Self test",
            brainRoot: "/tmp/Brain",
            cmuxPath: "/bin/cmux",
            commandOverride: "echo ok",
            focus: false
        )

        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--command")! + 1], "echo ok")
        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--focus")! + 1], "false")
    }

    func testParsesWorkspaceRefFromCmuxCreateOutput() {
        XCTAssertEqual(CmuxFocusLauncher.workspaceRef(from: "OK workspace:123"), "workspace:123")
        XCTAssertEqual(CmuxFocusLauncher.workspaceRef(from: "notice\nOK workspace:456\n"), "workspace:456")
        XCTAssertNil(CmuxFocusLauncher.workspaceRef(from: "OK"))
    }

    func testLaunchSelectsCreatedWorkspaceWhenFocused() throws {
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
            "if [ \"$1\" = \"workspace\" ] && [ \"$2\" = \"create\" ]; then",
            "  echo 'OK workspace:999'",
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
        XCTAssertTrue(calls.contains("workspace create"))
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
            "printf 'Failed to write to socket (Broken pipe, errno 32)\\n' >&2",
            "exit 1",
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
            "echo OK",
            "exit 0",
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
}
