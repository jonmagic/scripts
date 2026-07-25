import Foundation

/// On-disk snapshot of the board so the app can paint before the network answers.
///
/// A live Projects API read costs roughly 550-700ms, and the network floor for any
/// request to api.github.com from this machine is about 320ms, so no live call can
/// feel instant. The cache is what makes the app usable on a hotkey.
public struct CachedBoard: Codable, Sendable {
    public var tasks: [FocusTask]
    public var etag: String?
    public var fetchedAt: Date

    public init(tasks: [FocusTask], etag: String?, fetchedAt: Date) {
        self.tasks = tasks
        self.etag = etag
        self.fetchedAt = fetchedAt
    }
}

public enum BoardCache {
    public static var defaultURL: URL {
        // Overridable so the end-to-end test never clobbers the real cache.
        if let override = BrainBoard.environment("WEEKLY_FOCUS_CACHE") {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/weekly-focus", isDirectory: true)
        return base.appendingPathComponent("board.json")
    }

    public static func load(from url: URL = defaultURL) -> CachedBoard? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedBoard.self, from: data)
    }

    public static func save(_ board: CachedBoard, to url: URL = defaultURL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(board) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporary = url.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}

/// Reads and writes the Brain Tasks board, backed by `BoardCache`.
///
/// The store deliberately separates "what can I show right now" from "go ask GitHub"
/// so the UI never blocks on the network. Completions apply to the cache immediately
/// and are reconciled by the next refresh.
public final class BoardTaskStore: @unchecked Sendable {
    /// One week of items. Scoping the fetch to the current iteration keeps the payload
    /// flat as the board accumulates history.
    public static let currentWeekQuery = "week:@current"

    private let client: ProjectsV2Client
    private let cacheURL: URL
    private let lock = NSLock()
    private var cached: CachedBoard?

    /// Bumped by every local write. A fetch that started before a write finishes
    /// after it would otherwise resurrect the task that was just completed.
    private var localWrites = 0

    public init(client: ProjectsV2Client, cacheURL: URL = BoardCache.defaultURL) {
        self.client = client
        self.cacheURL = cacheURL
        self.cached = BoardCache.load(from: cacheURL)
    }

    public convenience init(cacheURL: URL = BoardCache.defaultURL) throws {
        self.init(client: ProjectsV2Client(token: try GitHubToken.resolve()), cacheURL: cacheURL)
    }

    public var cachedTasks: [FocusTask]? {
        lock.withLock { cached?.tasks }
    }

    public var lastFetchedAt: Date? {
        lock.withLock { cached?.fetchedAt }
    }

    @discardableResult
    public func refresh() async throws -> [FocusTask] {
        let (etag, writesAtStart) = lock.withLock { (cached?.etag, localWrites) }

        let result = try await client.fetchItems(query: Self.currentWeekQuery, etag: etag)

        return lock.withLock {
            // A local write landed while this fetch was in flight, so the response
            // predates it. Keep the optimistic state; the next refresh reconciles.
            guard localWrites == writesAtStart else {
                return cached?.tasks ?? []
            }

            if let tasks = result.tasks {
                let board = CachedBoard(tasks: tasks, etag: result.etag, fetchedAt: Date())
                cached = board
                BoardCache.save(board, to: cacheURL)
                return tasks
            }

            // 304: the board has not changed, so only the freshness stamp moves.
            if var board = cached {
                board.fetchedAt = Date()
                cached = board
                BoardCache.save(board, to: cacheURL)
                return board.tasks
            }

            return []
        }
    }

    /// Marks a task Done and stamps Reviewed, applying the change locally first so the
    /// UI updates immediately.
    public func complete(_ task: FocusTask) async throws {
        applyLocally(id: task.id) { existing in
            FocusTask(
                id: existing.id,
                nodeID: existing.nodeID,
                title: existing.title,
                status: "Done",
                statusOptionID: BrainBoard.Status.done,
                focus: existing.focus,
                week: existing.week,
                weekStart: existing.weekStart,
                source: existing.source,
                target: existing.target,
                area: existing.area
            )
        }

        do {
            try await client.update(itemID: task.id, fields: [
                .init(id: BrainBoard.Field.status, value: BrainBoard.Status.done),
                .init(id: BrainBoard.Field.reviewed, value: Self.today())
            ])
        } catch {
            // Put the optimistic change back if GitHub rejected it.
            applyLocally(id: task.id) { _ in task }
            throw error
        }
    }

    /// Adds a task to the current week as Todo.
    public func add(title: String, target: String? = nil, source: String? = nil) async throws {
        let title = Self.normalizedTitle(title)
        guard !title.isEmpty else {
            throw WeeklyFocusError.writeFailed("Task text is required")
        }

        noteLocalWrite()

        var fields: [ProjectsV2Client.FieldUpdate] = [
            .init(id: BrainBoard.Field.status, value: BrainBoard.Status.todo)
        ]
        if let target, !target.isEmpty {
            fields.append(.init(id: BrainBoard.Field.target, value: target))
        }
        if let source, !source.isEmpty {
            fields.append(.init(id: BrainBoard.Field.source, value: source))
        }

        _ = try await client.createDraft(title: title, fields: fields)
        _ = try await refresh()
    }

    private func noteLocalWrite() {
        lock.withLock { localWrites += 1 }
    }

    private func applyLocally(id: Int, transform: (FocusTask) -> FocusTask) {
        lock.withLock {
            localWrites += 1

            guard var board = cached, let index = board.tasks.firstIndex(where: { $0.id == id }) else {
                return
            }

            board.tasks[index] = transform(board.tasks[index])
            cached = board
            BoardCache.save(board, to: cacheURL)
        }
    }

    /// Board titles are single-line, so collapse pasted text rather than letting a
    /// newline land in the middle of a title.
    static func normalizedTitle(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
