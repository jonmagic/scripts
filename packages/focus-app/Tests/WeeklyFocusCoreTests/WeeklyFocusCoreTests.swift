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
            #"zsh -lic 'c -i "$WEEKLY_FOCUS_PROMPT" || copilot --allow-all -i "$WEEKLY_FOCUS_PROMPT"'"#
        )
        XCTAssertTrue(command.arguments[command.arguments.firstIndex(of: "--env")! + 1].contains(todo))
        XCTAssertFalse(command.arguments[command.arguments.firstIndex(of: "--command")! + 1].contains(todo))
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
