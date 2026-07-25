import Foundation

/// Identifiers for the Brain Tasks board (private Projects V2 board on `jonmagic/brain`).
///
/// The REST Projects API addresses fields by their numeric id, so these are captured
/// once here rather than discovered on every launch. `ProjectsV2Client.fields()` can
/// refresh them if the board is ever rebuilt.
public enum BrainBoard {
    /// Board coordinates default to @jonmagic's private Brain Tasks board but can be
    /// pointed elsewhere without a rebuild. This repository is public, so nothing that
    /// lives on the board itself (titles, sources, targets) belongs in it.
    public static var owner: String {
        environment("WEEKLY_FOCUS_PROJECT_OWNER") ?? "jonmagic"
    }

    public static var projectNumber: Int {
        environment("WEEKLY_FOCUS_PROJECT_NUMBER").flatMap(Int.init) ?? 6
    }

    public static var projectNodeID: String {
        environment("WEEKLY_FOCUS_PROJECT_NODE_ID") ?? "PVT_kwHNAm_OAXnL6Q"
    }

    public static func environment(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else {
            return nil
        }

        return value
    }

    public enum Field {
        public static let title = 372_695_107
        public static let status = 372_695_109
        public static let week = 372_695_315
        public static let focus = 372_695_329
        public static let source = 372_695_330
        public static let target = 372_695_331
        public static let reviewed = 372_695_332
        public static let area = 372_695_333

        public static let all = [title, status, week, focus, source, target, reviewed, area]
    }

    /// Status option ids. `single_select` writes require the option id, not its name.
    public enum Status {
        public static let inbox = "bb8e27d2"
        public static let todo = "1c1703bf"
        public static let doing = "7e587173"
        public static let waiting = "fc315b12"
        public static let done = "d976124a"
    }
}

/// A single task as it exists on the board.
public struct FocusTask: Equatable, Sendable, Codable {
    /// Numeric item id used by the REST API for `PATCH`.
    public let id: Int
    /// GraphQL node id, needed for mutations REST cannot express.
    public let nodeID: String
    public let title: String
    public let status: String
    public let statusOptionID: String?
    public let focus: Int?
    public let week: String?
    public let weekStart: String?
    public let source: String?
    public let target: String?
    public let area: String?

    public init(
        id: Int,
        nodeID: String,
        title: String,
        status: String,
        statusOptionID: String? = nil,
        focus: Int? = nil,
        week: String? = nil,
        weekStart: String? = nil,
        source: String? = nil,
        target: String? = nil,
        area: String? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.title = title
        self.status = status
        self.statusOptionID = statusOptionID
        self.focus = focus
        self.week = week
        self.weekStart = weekStart
        self.source = source
        self.target = target
        self.area = area
    }

    /// What the app renders. The board keeps the target in its own field, so the
    /// title stays clean instead of carrying a trailing URL the way markdown did.
    public var displayText: String {
        title
    }

    /// The string the action resolver inspects. Targets live in their own field now,
    /// but older rows mirrored from markdown may still carry the target inline.
    public var actionText: String {
        guard let target = target?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            return title
        }

        return "\(title) \(target)"
    }

    public var isOpen: Bool {
        switch status {
        case "Done", "Dropped":
            return false
        default:
            return true
        }
    }

    public var isWaiting: Bool {
        status == "Waiting"
    }
}

/// Ordering used for the focus list: explicit Focus numbers first, then the board's
/// own order. Without a stable tiebreaker the list would shuffle between refreshes.
public func focusOrdered(_ tasks: [FocusTask]) -> [FocusTask] {
    tasks.enumerated().sorted { lhs, rhs in
        switch (lhs.element.focus, rhs.element.focus) {
        case let (l?, r?):
            return l == r ? lhs.offset < rhs.offset : l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.offset < rhs.offset
        }
    }.map(\.element)
}
