import Foundation

/// Chooses between the board and the weekly note, and keeps the UI off the network.
///
/// The board is canonical. Markdown remains a fallback so the app still works when
/// there is no token or GitHub is unreachable, which matters because this is a
/// hotkey app that should never fail to paint.
///
/// Credentials are resolved lazily and never on the paint path. Reading the cache
/// needs no auth, and the first Keychain read for a freshly built binary can block
/// for seconds while macOS authorizes it, which would otherwise stall launch.
public final class FocusSource: @unchecked Sendable {
    public enum Backing: Equatable, Sendable {
        case board
        case markdown
    }

    private let reader: WeeklyFocusReader
    private let cacheURL: URL
    private let makeStore: (@Sendable () throws -> BoardTaskStore)?
    private let lock = NSLock()
    private var store: BoardTaskStore?

    public var weeklyNotePath: String {
        reader.weeklyNotePath
    }

    public var brainRoot: String {
        reader.brainRoot
    }

    /// Whether the board is configured. This deliberately does not touch the Keychain,
    /// so it is safe to call while laying out the window.
    public var isBoardEnabled: Bool {
        makeStore != nil
    }

    /// The board factory used by default. Returns nil when the board is switched off,
    /// which keeps offline use and markdown-only tests honest.
    public static var defaultStoreFactory: (@Sendable () throws -> BoardTaskStore)? {
        guard BrainBoard.environment("WEEKLY_FOCUS_DISABLE_BOARD") == nil else {
            return nil
        }

        return { try BoardTaskStore() }
    }

    public init(
        reader: WeeklyFocusReader = WeeklyFocusReader(),
        cacheURL: URL = BoardCache.defaultURL,
        makeStore: (@Sendable () throws -> BoardTaskStore)? = FocusSource.defaultStoreFactory
    ) {
        self.reader = reader
        self.cacheURL = cacheURL
        self.makeStore = makeStore
    }

    /// A source that only ever touches the weekly note. Used by the self-test so it
    /// never writes throwaway items to the real board.
    public static func markdownOnly(reader: WeeklyFocusReader = WeeklyFocusReader()) -> FocusSource {
        FocusSource(reader: reader, makeStore: nil)
    }

    private func boardStore() throws -> BoardTaskStore {
        if let existing = lock.withLock({ store }) {
            return existing
        }

        guard let makeStore else {
            throw WeeklyFocusError.writeFailed("board is disabled")
        }

        let created = try makeStore()
        return lock.withLock {
            if let existing = store {
                return existing
            }

            store = created
            return created
        }
    }

    /// Returns immediately and without authenticating. Uses the cached board when it
    /// has been populated, and the weekly note otherwise, so a cold first launch still
    /// shows something useful.
    public func currentSnapshot(
        todoLimit: Int = 5,
        overflowLimit: Int? = nil,
        waitingLimit: Int = 3
    ) throws -> WeeklyFocusSnapshot {
        if isBoardEnabled, let cached = BoardCache.load(from: cacheURL), !cached.tasks.isEmpty {
            return WeeklyFocusSnapshot.fromBoard(
                cached.tasks,
                brainRoot: reader.brainRoot,
                weeklyNotePath: reader.weeklyNotePath,
                todoLimit: todoLimit,
                overflowLimit: overflowLimit,
                waitingLimit: waitingLimit
            )
        }

        return try reader.read(
            todoLimit: todoLimit,
            overflowLimit: overflowLimit,
            waitingLimit: waitingLimit
        )
    }

    /// Pulls fresh board state. Throws when the board is unavailable so the caller can
    /// decide whether to surface the failure or keep showing cached data.
    public func refreshed(
        todoLimit: Int = 5,
        overflowLimit: Int? = nil,
        waitingLimit: Int = 3
    ) async throws -> WeeklyFocusSnapshot {
        guard isBoardEnabled else {
            return try reader.read(
                todoLimit: todoLimit,
                overflowLimit: overflowLimit,
                waitingLimit: waitingLimit
            )
        }

        let tasks = try await boardStore().refresh()
        return WeeklyFocusSnapshot.fromBoard(
            tasks,
            brainRoot: reader.brainRoot,
            weeklyNotePath: reader.weeklyNotePath,
            todoLimit: todoLimit,
            overflowLimit: overflowLimit,
            waitingLimit: waitingLimit
        )
    }

    @discardableResult
    public func complete(
        _ snapshot: WeeklyFocusSnapshot,
        at index: Int
    ) async throws -> Backing {
        if isBoardEnabled, snapshot.isBoardBacked, snapshot.tasks.indices.contains(index) {
            try await boardStore().complete(snapshot.tasks[index])
            return .board
        }

        guard snapshot.todos.indices.contains(index) else {
            throw WeeklyFocusError.todoNotFound("index \(index)")
        }

        try WeeklyFocusReader.markTodoDone(
            snapshot.todos[index],
            weeklyNotePath: snapshot.weeklyNotePath
        )
        return .markdown
    }

    @discardableResult
    public func add(_ text: String, source: String? = nil) async throws -> Backing {
        if isBoardEnabled {
            try await boardStore().add(title: text, source: source)
            return .board
        }

        try WeeklyFocusReader.appendTodo(text, weeklyNotePath: reader.weeklyNotePath)
        return .markdown
    }

    /// The string the action resolver should inspect for a session id, URL, or wikilink.
    public static func actionText(for snapshot: WeeklyFocusSnapshot, at index: Int) -> String? {
        if snapshot.isBoardBacked, snapshot.tasks.indices.contains(index) {
            return snapshot.tasks[index].actionText
        }

        guard snapshot.todos.indices.contains(index) else {
            return nil
        }

        return snapshot.todos[index]
    }
}
