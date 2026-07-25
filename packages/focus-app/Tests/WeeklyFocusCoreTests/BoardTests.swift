import XCTest
@testable import WeeklyFocusCore

/// Fixtures here are synthetic on purpose. This repository is public and the real
/// board carries private Brain references in its Source and Target fields.
private func itemJSON(
    id: Int,
    nodeID: String,
    title: String,
    status: (id: String, name: String)? = nil,
    focus: Int? = nil,
    week: (title: String, start: String)? = nil,
    target: String? = nil
) -> String {
    var fields: [String] = [
        """
        {"id":\(BrainBoard.Field.title),"name":"Title","data_type":"title",
         "value":{"raw":"\(title)","html":"\(title)"}}
        """
    ]

    if let status {
        fields.append("""
        {"id":\(BrainBoard.Field.status),"name":"Status","data_type":"single_select",
         "value":{"id":"\(status.id)","name":{"raw":"\(status.name)","html":"\(status.name)"},"color":"BLUE"}}
        """)
    }

    if let focus {
        fields.append("""
        {"id":\(BrainBoard.Field.focus),"name":"Focus","data_type":"number","value":\(focus)}
        """)
    }

    if let week {
        fields.append("""
        {"id":\(BrainBoard.Field.week),"name":"Week","data_type":"iteration",
         "value":{"id":"it1","start_date":"\(week.start)","duration":7,
                  "title":{"raw":"\(week.title)","html":"\(week.title)"},"completed":false}}
        """)
    }

    if let target {
        fields.append("""
        {"id":\(BrainBoard.Field.target),"name":"Target","data_type":"text",
         "value":{"raw":"\(target)","html":"\(target)"}}
        """)
    }

    fields.append("""
    {"id":\(BrainBoard.Field.reviewed),"name":"Reviewed","data_type":"date","value":null}
    """)

    return """
    {"id":\(id),"node_id":"\(nodeID)","fields":[\(fields.joined(separator: ","))]}
    """
}

final class ProjectsV2DecoderTests: XCTestCase {
    func testDecodesEveryFieldShapeTheAPIReturns() throws {
        let json = "[\(itemJSON(id: 101, nodeID: "PVTI_a", title: "Ship the thing", status: (BrainBoard.Status.todo, "Todo"), focus: 2, week: ("Week of 2026-07-19", "2026-07-19"), target: "https://example.com/x"))]"

        let tasks = try ProjectsV2Decoder.tasks(from: Data(json.utf8))
        XCTAssertEqual(tasks.count, 1)

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.id, 101)
        XCTAssertEqual(task.nodeID, "PVTI_a")
        XCTAssertEqual(task.title, "Ship the thing")
        XCTAssertEqual(task.status, "Todo")
        XCTAssertEqual(task.statusOptionID, BrainBoard.Status.todo)
        XCTAssertEqual(task.focus, 2)
        XCTAssertEqual(task.week, "Week of 2026-07-19")
        XCTAssertEqual(task.weekStart, "2026-07-19")
        XCTAssertEqual(task.target, "https://example.com/x")
    }

    func testToleratesMissingAndNullValues() throws {
        let json = "[\(itemJSON(id: 7, nodeID: "PVTI_b", title: "Bare item"))]"
        let tasks = try ProjectsV2Decoder.tasks(from: Data(json.utf8))
        let task = try XCTUnwrap(tasks.first)

        XCTAssertEqual(task.title, "Bare item")
        XCTAssertTrue(task.status.isEmpty)
        XCTAssertNil(task.focus)
        XCTAssertNil(task.week)
        XCTAssertNil(task.target)
    }

    func testActionTextFallsBackToTitleWithoutTarget() {
        let bare = FocusTask(id: 1, nodeID: "n", title: "Do a thing", status: "Todo")
        XCTAssertEqual(bare.actionText, "Do a thing")

        let targeted = FocusTask(
            id: 2, nodeID: "n", title: "Do a thing", status: "Todo", target: "https://example.com"
        )
        XCTAssertEqual(targeted.actionText, "Do a thing https://example.com")
        XCTAssertEqual(targeted.displayText, "Do a thing")
    }

    func testOpenAndWaitingStatesAreDerivedFromStatus() {
        XCTAssertTrue(FocusTask(id: 1, nodeID: "n", title: "t", status: "Todo").isOpen)
        XCTAssertTrue(FocusTask(id: 1, nodeID: "n", title: "t", status: "Doing").isOpen)
        XCTAssertFalse(FocusTask(id: 1, nodeID: "n", title: "t", status: "Done").isOpen)
        XCTAssertFalse(FocusTask(id: 1, nodeID: "n", title: "t", status: "Dropped").isOpen)
        XCTAssertTrue(FocusTask(id: 1, nodeID: "n", title: "t", status: "Waiting").isWaiting)
    }
}

final class FocusOrderingTests: XCTestCase {
    func testFocusNumbersSortFirstAndUnrankedKeepBoardOrder() {
        let tasks = [
            FocusTask(id: 1, nodeID: "n", title: "unranked a", status: "Todo"),
            FocusTask(id: 2, nodeID: "n", title: "focus 2", status: "Todo", focus: 2),
            FocusTask(id: 3, nodeID: "n", title: "unranked b", status: "Todo"),
            FocusTask(id: 4, nodeID: "n", title: "focus 1", status: "Todo", focus: 1)
        ]

        XCTAssertEqual(
            focusOrdered(tasks).map(\.title),
            ["focus 1", "focus 2", "unranked a", "unranked b"]
        )
    }

    func testOrderingIsStableForDuplicateFocusValues() {
        let tasks = [
            FocusTask(id: 1, nodeID: "n", title: "first", status: "Todo", focus: 1),
            FocusTask(id: 2, nodeID: "n", title: "second", status: "Todo", focus: 1)
        ]

        XCTAssertEqual(focusOrdered(tasks).map(\.title), ["first", "second"])
    }
}

final class BoardSnapshotTests: XCTestCase {
    private func task(_ title: String, _ status: String, id: Int = 0, focus: Int? = nil) -> FocusTask {
        FocusTask(id: id, nodeID: "n", title: title, status: status, focus: focus)
    }

    func testSplitsOpenWaitingAndCompletedCounts() {
        let snapshot = WeeklyFocusSnapshot.fromBoard(
            [
                task("a", "Todo", id: 1, focus: 1),
                task("b", "Todo", id: 2, focus: 2),
                task("w", "Waiting", id: 3),
                task("d", "Done", id: 4),
                task("x", "Dropped", id: 5)
            ],
            brainRoot: "/tmp/brain",
            weeklyNotePath: "/tmp/brain/note.md"
        )

        XCTAssertEqual(snapshot.todos, ["a", "b"])
        XCTAssertEqual(snapshot.waiting, ["w"])
        XCTAssertEqual(snapshot.capturedCount, 2)
        XCTAssertTrue(snapshot.isBoardBacked)
        XCTAssertEqual(snapshot.now, "a")
        XCTAssertEqual(snapshot.next, "b")
    }

    func testLimitsFocusListAndRoutesRestToOverflow() {
        let tasks = (1...9).map { task("t\($0)", "Todo", id: $0, focus: $0) }
        let snapshot = WeeklyFocusSnapshot.fromBoard(
            tasks,
            brainRoot: "/tmp/brain",
            weeklyNotePath: "/tmp/brain/note.md",
            todoLimit: 5,
            overflowLimit: 2
        )

        XCTAssertEqual(snapshot.todos, ["t1", "t2", "t3", "t4", "t5"])
        XCTAssertEqual(snapshot.overflowTodos, ["t6", "t7"])
        XCTAssertEqual(snapshot.tasks.count, 5)
    }

    func testMarkdownSnapshotsAreNotBoardBacked() {
        let snapshot = WeeklyFocusSnapshot(
            brainRoot: "/tmp/brain",
            weeklyNotePath: "/tmp/brain/note.md",
            todos: ["a"],
            waiting: [],
            capturedCount: 0
        )

        XCTAssertFalse(snapshot.isBoardBacked)
        XCTAssertTrue(snapshot.tasks.isEmpty)
    }
}

final class LinkHeaderTests: XCTestCase {
    private func response(link: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/x")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: link.map { ["Link": $0] }
        )!
    }

    func testExtractsNextCursor() {
        let header = "<https://api.github.com/x?after=abc>; rel=\"next\", <https://api.github.com/x>; rel=\"first\""
        XCTAssertEqual(
            ProjectsV2Client.nextLink(from: response(link: header))?.absoluteString,
            "https://api.github.com/x?after=abc"
        )
    }

    func testReturnsNilOnLastPage() {
        XCTAssertNil(ProjectsV2Client.nextLink(from: response(link: "<https://api.github.com/x>; rel=\"prev\"")))
        XCTAssertNil(ProjectsV2Client.nextLink(from: response(link: nil)))
    }
}

final class BoardCacheTests: XCTestCase {
    func testRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-test-\(UUID().uuidString)")
            .appendingPathComponent("board.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let board = CachedBoard(
            tasks: [FocusTask(id: 5, nodeID: "n", title: "cached", status: "Todo", focus: 1)],
            etag: "W/\"abc\"",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        BoardCache.save(board, to: url)
        let loaded = try XCTUnwrap(BoardCache.load(from: url))

        XCTAssertEqual(loaded.tasks, board.tasks)
        XCTAssertEqual(loaded.etag, "W/\"abc\"")
        XCTAssertEqual(Int(loaded.fetchedAt.timeIntervalSince1970), 1_700_000_000)
    }

    func testMissingCacheLoadsAsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-missing-\(UUID().uuidString).json")
        XCTAssertNil(BoardCache.load(from: url))
    }
}

final class TodayStampTests: XCTestCase {
    func testFormatsReviewedStampTheWayTheAPIExpects() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5))!

        XCTAssertEqual(BoardTaskStore.today(date, calendar: calendar), "2026-07-05")
    }
}

final class FocusSourceTests: XCTestCase {
    private func makeWeeklyNote() throws -> (root: String, path: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-src-\(UUID().uuidString)")
        let notes = root.appendingPathComponent("Weekly Notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)

        let path = notes.appendingPathComponent("Week of 2026-07-19.md")
        try """
        # Week

        ## TODO
        - [ ] markdown item

        ## Waiting
        - [ ] waiting item
        """.write(to: path, atomically: true, encoding: .utf8)

        return (root.path, path.path)
    }

    func testMarkdownOnlySourceIgnoresTheBoard() throws {
        let note = try makeWeeklyNote()
        defer { try? FileManager.default.removeItem(atPath: note.root) }

        let source = FocusSource.markdownOnly(
            reader: WeeklyFocusReader(brainRoot: note.root, weeklyNotePath: note.path)
        )

        XCTAssertFalse(source.isBoardEnabled)
        let snapshot = try source.currentSnapshot()
        XCTAssertEqual(snapshot.todos, ["markdown item"])
        XCTAssertFalse(snapshot.isBoardBacked)
    }

    func testCurrentSnapshotPrefersCachedBoardWithoutAuthenticating() throws {
        let note = try makeWeeklyNote()
        defer { try? FileManager.default.removeItem(atPath: note.root) }

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-cache-\(UUID().uuidString)")
            .appendingPathComponent("board.json")
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

        BoardCache.save(
            CachedBoard(
                tasks: [FocusTask(id: 1, nodeID: "n", title: "board item", status: "Todo", focus: 1)],
                etag: nil,
                fetchedAt: Date()
            ),
            to: cacheURL
        )

        // A store factory that would fail if called proves the paint path never authenticates.
        let source = FocusSource(
            reader: WeeklyFocusReader(brainRoot: note.root, weeklyNotePath: note.path),
            cacheURL: cacheURL,
            makeStore: { throw GitHubToken.Failure.notFound }
        )

        let snapshot = try source.currentSnapshot()
        XCTAssertEqual(snapshot.todos, ["board item"])
        XCTAssertTrue(snapshot.isBoardBacked)
    }

    func testFallsBackToMarkdownWhenCacheIsEmpty() throws {
        let note = try makeWeeklyNote()
        defer { try? FileManager.default.removeItem(atPath: note.root) }

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-empty-\(UUID().uuidString).json")

        let source = FocusSource(
            reader: WeeklyFocusReader(brainRoot: note.root, weeklyNotePath: note.path),
            cacheURL: cacheURL,
            makeStore: { throw GitHubToken.Failure.notFound }
        )

        let snapshot = try source.currentSnapshot()
        XCTAssertEqual(snapshot.todos, ["markdown item"])
        XCTAssertFalse(snapshot.isBoardBacked)
    }

    func testActionTextPrefersBoardTargetOverTitle() {
        let boardSnapshot = WeeklyFocusSnapshot.fromBoard(
            [FocusTask(id: 1, nodeID: "n", title: "do it", status: "Todo", target: "https://example.com/a")],
            brainRoot: "/tmp",
            weeklyNotePath: "/tmp/n.md"
        )
        XCTAssertEqual(FocusSource.actionText(for: boardSnapshot, at: 0), "do it https://example.com/a")

        let markdownSnapshot = WeeklyFocusSnapshot(
            brainRoot: "/tmp", weeklyNotePath: "/tmp/n.md",
            todos: ["plain todo"], waiting: [], capturedCount: 0
        )
        XCTAssertEqual(FocusSource.actionText(for: markdownSnapshot, at: 0), "plain todo")
        XCTAssertNil(FocusSource.actionText(for: markdownSnapshot, at: 3))
    }
}
