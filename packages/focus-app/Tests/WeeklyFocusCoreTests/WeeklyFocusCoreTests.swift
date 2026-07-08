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
        XCTAssertTrue(command.arguments.contains("new-workspace"))
        XCTAssertEqual(command.arguments[command.arguments.firstIndex(of: "--cwd")! + 1], "/tmp/Brain")
        XCTAssertEqual(
            command.arguments[command.arguments.firstIndex(of: "--command")! + 1],
            #"if command -v c >/dev/null 2>&1; then c -i "$WEEKLY_FOCUS_PROMPT"; else copilot --allow-all -i "$WEEKLY_FOCUS_PROMPT"; fi"#
        )
        XCTAssertTrue(command.arguments[command.arguments.firstIndex(of: "--env")! + 1].contains(todo))
        XCTAssertFalse(command.arguments[command.arguments.firstIndex(of: "--command")! + 1].contains(todo))
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
