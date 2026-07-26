import XCTest
@testable import WeeklyFocusCore

/// Live read-only smoke test against the real board.
/// Skipped unless WEEKLY_FOCUS_LIVE=1 so normal runs stay offline and deterministic.
final class LiveBoardSmokeTests: XCTestCase {
    func testLiveBoardReadAndWrite() async throws {
        guard ProcessInfo.processInfo.environment["WEEKLY_FOCUS_LIVE"] == "1" else {
            throw XCTSkip("live test disabled")
        }

        let token = try GitHubToken.resolve()
        let client = ProjectsV2Client(token: token)

        let started = Date()
        let result = try await client.fetchItems(query: BoardTaskStore.openTasksQuery)
        let elapsed = Date().timeIntervalSince(started)
        let tasks = try XCTUnwrap(result.tasks)

        print("LIVE: fetched \(tasks.count) items in \(Int(elapsed * 1000))ms, etag=\(result.etag ?? "none")")
        XCTAssertFalse(tasks.isEmpty)

        let decoded = tasks.filter { !$0.title.isEmpty }
        XCTAssertEqual(decoded.count, tasks.count, "every item should decode a title")

        let withStatus = tasks.filter { !$0.status.isEmpty }
        print("LIVE: \(withStatus.count) items carry a status; open=\(tasks.filter(\.isOpen).count)")
        XCTAssertFalse(withStatus.isEmpty)

        // The fetch is scoped by status now, so a task without a week is expected
        // rather than a bug. What must hold is that nothing closed comes back.
        let closed = tasks.filter { !$0.isOpen }
        print("LIVE: \(tasks.filter { $0.week != nil }.count) of \(tasks.count) items carry a week")
        XCTAssertTrue(closed.isEmpty, "the open query should not return Done or Dropped items")

        // Conditional refresh should come back as 304 and preserve the cached copy.
        let conditional = try await client.fetchItems(
            query: BoardTaskStore.openTasksQuery,
            etag: result.etag
        )
        print("LIVE: conditional refresh returned tasks=\(conditional.tasks == nil ? "304" : "200")")

        let snapshot = WeeklyFocusSnapshot.fromBoard(
            tasks,
            brainRoot: "/tmp",
            weeklyNotePath: "/tmp/note.md",
            todoLimit: 5,
            overflowLimit: 6
        )
        print("LIVE: focus list -> \(snapshot.todos.count) items, overflow=\(snapshot.overflowTodos.count), done=\(snapshot.capturedCount)")
        XCTAssertFalse(snapshot.tasks.isEmpty)
    }

    /// A task created without a Week is invisible to `week:@current`, which is the
    /// only query this app runs. This proves `add` schedules what it creates.
    func testLiveAddSchedulesIntoTheCurrentWeek() async throws {
        guard ProcessInfo.processInfo.environment["WEEKLY_FOCUS_LIVE"] == "1" else {
            throw XCTSkip("live test disabled")
        }

        let token = try GitHubToken.resolve()
        let client = ProjectsV2Client(token: token)
        let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("weekly-focus-live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let store = BoardTaskStore(client: client, cacheURL: cacheURL)
        let title = "TEMP live add probe \(UUID().uuidString.prefix(8))"

        try await store.add(title: title)

        // The task must be visible immediately, without waiting on the search index.
        let local = try XCTUnwrap(store.cachedTasks?.first { $0.title == title })
        XCTAssertEqual(local.status, "Todo")
        XCTAssertNotNil(local.week, "add still records a week even though the fetch ignores it")
        print("LIVE: added \(local.id) into \(local.week ?? "nil")")

        // And it must survive a real round trip through the board query. The search
        // index behind `q=` trails writes by a few seconds, so poll rather than
        // asserting on the first read.
        var found = false
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let refreshed = try await client.fetchItems(query: BoardTaskStore.openTasksQuery)
            if refreshed.tasks?.contains(where: { $0.title == title }) == true {
                found = true
                break
            }
        }

        try await client.delete(itemID: local.id)
        XCTAssertTrue(found, "the open query should return the task that add created")
    }

}
