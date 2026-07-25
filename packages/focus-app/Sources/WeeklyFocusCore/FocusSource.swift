import Foundation

/// Reads and writes the task board, and keeps the UI off the network.
///
/// The board is the only task source. There is no markdown fallback: a second source
/// meant completions could silently land somewhere the rest of the system never sees.
/// What protects the hotkey launch is the cache, not an alternate backend.
///
/// Credentials are resolved lazily and never on the paint path. Reading the cache needs
/// no auth, and the first Keychain read for a freshly built binary can block for
/// seconds while macOS authorizes it, which would otherwise stall launch.
public final class FocusSource: @unchecked Sendable {
    private let paths: BrainPaths
    private let cacheURL: URL
    private let makeStore: @Sendable () throws -> BoardTaskStore
    private let lock = NSLock()
    private var store: BoardTaskStore?

    public var weeklyNotePath: String {
        paths.weeklyNotePath
    }

    public var brainRoot: String {
        paths.brainRoot
    }

    public init(
        paths: BrainPaths = BrainPaths(),
        cacheURL: URL = BoardCache.defaultURL,
        makeStore: @escaping @Sendable () throws -> BoardTaskStore = { try BoardTaskStore() }
    ) {
        self.paths = paths
        self.cacheURL = cacheURL
        self.makeStore = makeStore
    }

    private func boardStore() throws -> BoardTaskStore {
        if let existing = lock.withLock({ store }) {
            return existing
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

    /// Returns immediately and without authenticating, from whatever the last refresh
    /// cached. Empty on a cold first launch, which the caller renders as an empty list
    /// rather than blocking.
    public func currentSnapshot(
        todoLimit: Int = 5,
        overflowLimit: Int? = nil,
        waitingLimit: Int = 3
    ) -> WeeklyFocusSnapshot {
        WeeklyFocusSnapshot.fromBoard(
            BoardCache.load(from: cacheURL)?.tasks ?? [],
            brainRoot: paths.brainRoot,
            weeklyNotePath: paths.weeklyNotePath,
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
        let tasks = try await boardStore().refresh()
        return WeeklyFocusSnapshot.fromBoard(
            tasks,
            brainRoot: paths.brainRoot,
            weeklyNotePath: paths.weeklyNotePath,
            todoLimit: todoLimit,
            overflowLimit: overflowLimit,
            waitingLimit: waitingLimit
        )
    }

    public func complete(_ snapshot: WeeklyFocusSnapshot, at index: Int) async throws {
        guard snapshot.tasks.indices.contains(index) else {
            throw WeeklyFocusError.todoNotFound("index \(index)")
        }

        try await boardStore().complete(snapshot.tasks[index])
    }

    public func add(_ text: String, source: String? = nil) async throws {
        try await boardStore().add(title: text, source: source)
    }

    /// The string the action resolver should inspect for a session id, URL, or wikilink.
    public static func actionText(for snapshot: WeeklyFocusSnapshot, at index: Int) -> String? {
        guard snapshot.tasks.indices.contains(index) else {
            return nil
        }

        return snapshot.tasks[index].actionText
    }
}
