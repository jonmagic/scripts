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
    /// Last resolved Week iteration. Kept so adding a task does not need a fields
    /// lookup every time; it is reused only while its start date is still this week.
    public var currentIteration: ProjectsV2Client.Iteration?

    public init(
        tasks: [FocusTask],
        etag: String?,
        fetchedAt: Date,
        currentIteration: ProjectsV2Client.Iteration? = nil
    ) {
        self.tasks = tasks
        self.etag = etag
        self.fetchedAt = fetchedAt
        self.currentIteration = currentIteration
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
    /// Every task that is still open, whatever week it carries.
    ///
    /// This deliberately mirrors `FocusTask.isOpen` so the server and the client
    /// agree on what "open" means. Scoping by week instead would make the app go
    /// blank whenever the weekly roll had not run yet, and it hid captured work
    /// that landed without a week.
    ///
    /// Excluding the closed statuses is also what keeps the payload flat: open work
    /// stays roughly constant while Done and Dropped accumulate forever.
    public static let openTasksQuery = "-status:Done -status:Dropped"

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

        let result = try await client.fetchItems(query: Self.openTasksQuery, etag: etag)

        return lock.withLock {
            // A local write landed while this fetch was in flight, so the response
            // predates it. Keep the optimistic state; the next refresh reconciles.
            guard localWrites == writesAtStart else {
                return cached?.tasks ?? []
            }

            if let tasks = result.tasks {
                let board = CachedBoard(
                    tasks: tasks,
                    etag: result.etag,
                    fetchedAt: Date(),
                    currentIteration: cached?.currentIteration
                )
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
    ///
    /// The week matters: the board view is scoped to `week:@current`, so a task
    /// created without one is invisible here until the next weekly roll moves it.
    public func add(title: String, target: String? = nil, source: String? = nil) async throws {
        let title = Self.normalizedTitle(title)
        guard !title.isEmpty else {
            throw WeeklyFocusError.writeFailed("Task text is required")
        }

        let iteration = try await currentIteration()

        var fields: [ProjectsV2Client.FieldUpdate] = [
            .init(id: BrainBoard.Field.status, value: BrainBoard.Status.todo),
            .init(id: BrainBoard.Field.week, value: iteration.id)
        ]
        if let target, !target.isEmpty {
            fields.append(.init(id: BrainBoard.Field.target, value: target))
        }
        if let source, !source.isEmpty {
            fields.append(.init(id: BrainBoard.Field.source, value: source))
        }

        noteLocalWrite()
        let created = try await client.createDraft(title: title, fields: fields)

        // The search index behind `q=` trails writes by a few seconds, so refreshing
        // here would usually answer without the task that was just added. Insert it
        // locally instead and let the next natural refresh reconcile.
        insertLocally(
            FocusTask(
                id: created.id,
                nodeID: created.nodeID,
                title: title,
                status: "Todo",
                statusOptionID: BrainBoard.Status.todo,
                week: iteration.title,
                weekStart: iteration.startDate,
                source: source,
                target: target
            )
        )
    }

    /// Resolves the week that `week:@current` matches, reusing the cached answer
    /// while it is still the current Sunday.
    func currentIteration(now: Date = Date(), calendar: Calendar = .current) async throws -> ProjectsV2Client.Iteration {
        let startOfWeek = Self.startOfWeek(now, calendar: calendar)

        if let cachedIteration = lock.withLock({ cached?.currentIteration }),
           cachedIteration.startDate == startOfWeek {
            return cachedIteration
        }

        let iterations = try await client.fetchIterations()
        guard let match = iterations.first(where: { $0.startDate == startOfWeek }) else {
            throw WeeklyFocusError.writeFailed(
                "The Week field has no iteration starting \(startOfWeek). Add more weeks to the board."
            )
        }

        lock.withLock {
            var board = cached ?? CachedBoard(tasks: [], etag: nil, fetchedAt: .distantPast)
            board.currentIteration = match
            cached = board
            BoardCache.save(board, to: cacheURL)
        }

        return match
    }

    /// Sunday that starts the week containing `now`, formatted like the board.
    static func startOfWeek(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.firstWeekday = 1
        let weekday = calendar.component(.weekday, from: now)
        let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: now) ?? now
        return today(start, calendar: calendar)
    }

    private func noteLocalWrite() {
        lock.withLock { localWrites += 1 }
    }

    private func insertLocally(_ task: FocusTask) {
        lock.withLock {
            var board = cached ?? CachedBoard(tasks: [], etag: nil, fetchedAt: Date())
            board.tasks.append(task)
            // The response this cache came from did not contain the new task, so the
            // etag would let a later 304 hide it.
            board.etag = nil
            cached = board
            BoardCache.save(board, to: cacheURL)
        }
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
