import Foundation

public struct WeeklyFocusSnapshot: Equatable {
    public let brainRoot: String
    public let weeklyNotePath: String
    public let todos: [String]
    public let waiting: [String]
    public let capturedCount: Int

    public var now: String? {
        todos.first
    }

    public var next: String? {
        todos.dropFirst().first
    }

    public init(
        brainRoot: String,
        weeklyNotePath: String,
        todos: [String],
        waiting: [String],
        capturedCount: Int
    ) {
        self.brainRoot = brainRoot
        self.weeklyNotePath = weeklyNotePath
        self.todos = todos
        self.waiting = waiting
        self.capturedCount = capturedCount
    }
}

public struct LaunchCommand: Equatable {
    public let executable: String
    public let arguments: [String]
}

public enum WeeklyFocusError: LocalizedError {
    case weeklyNoteMissing(String)

    public var errorDescription: String? {
        switch self {
        case .weeklyNoteMissing(let path):
            return "Weekly note not found: \(path)"
        }
    }
}

public struct WeeklyFocusReader {
    public let brainRoot: String
    public let weeklyNotePath: String

    public init(
        brainRoot: String = WeeklyFocusReader.defaultBrainRoot(),
        date: Date = Date(),
        weeklyNotePath: String? = nil,
        calendar: Calendar = .current
    ) {
        let resolvedBrainRoot = WeeklyFocusReader.resolveHome(brainRoot)
        self.brainRoot = resolvedBrainRoot
        self.weeklyNotePath = weeklyNotePath ?? WeeklyFocusReader.weeklyNotePath(
            brainRoot: resolvedBrainRoot,
            date: date,
            calendar: calendar
        )
    }

    public func read(todoLimit: Int = 5, waitingLimit: Int = 3) throws -> WeeklyFocusSnapshot {
        guard FileManager.default.fileExists(atPath: weeklyNotePath) else {
            throw WeeklyFocusError.weeklyNoteMissing(weeklyNotePath)
        }

        let content = try String(contentsOfFile: weeklyNotePath, encoding: .utf8)
        return Self.parse(
            content,
            brainRoot: brainRoot,
            weeklyNotePath: weeklyNotePath,
            todoLimit: todoLimit,
            waitingLimit: waitingLimit
        )
    }

    public static func defaultBrainRoot() -> String {
        if let root = ProcessInfo.processInfo.environment["BRAIN_ROOT"], !root.isEmpty {
            return root
        }

        return "~/Brain"
    }

    public static func resolveHome(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }

        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            return URL(fileURLWithPath: suffix, relativeTo: FileManager.default.homeDirectoryForCurrentUser).path
        }

        return path
    }

    public static func weeklyNotePath(
        brainRoot: String,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        let weekStart = startOfWeekSunday(date, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return URL(fileURLWithPath: brainRoot)
            .appendingPathComponent("Weekly Notes")
            .appendingPathComponent("Week of \(formatter.string(from: weekStart)).md")
            .path
    }

    public static func parse(
        _ content: String,
        brainRoot: String,
        weeklyNotePath: String,
        todoLimit: Int = 5,
        waitingLimit: Int = 3
    ) -> WeeklyFocusSnapshot {
        let lines = content.components(separatedBy: .newlines)
        let todoItems = uncheckedItems(in: lines, heading: "## TODO")
        let waitingItems = uncheckedItems(in: lines, heading: "## Waiting")
        let todos = Array(todoItems[..<Swift.min(todoItems.count, Swift.max(0, todoLimit))])
        let waiting = Array(waitingItems[..<Swift.min(waitingItems.count, Swift.max(0, waitingLimit))])
        let capturedCount = uncheckedItems(in: lines, heading: "## Captured").count

        return WeeklyFocusSnapshot(
            brainRoot: brainRoot,
            weeklyNotePath: weeklyNotePath,
            todos: todos,
            waiting: waiting,
            capturedCount: capturedCount
        )
    }

    private static func startOfWeekSunday(
        _ date: Date,
        calendar inputCalendar: Calendar
    ) -> Date {
        var calendar = inputCalendar
        calendar.firstWeekday = 1
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfDay) ?? startOfDay
    }

    private static func uncheckedItems(in lines: [String], heading: String) -> [String] {
        guard let bounds = sectionBounds(in: lines, heading: heading) else {
            return []
        }

        return lines[bounds.start..<bounds.end].compactMap { line in
            guard line.hasPrefix("- [ ] ") else {
                return nil
            }

            return String(line.dropFirst("- [ ] ".count)).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func sectionBounds(in lines: [String], heading: String) -> (start: Int, end: Int)? {
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
            return nil
        }

        let start = headingIndex + 1
        let end = lines[start...].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.count
        return (start, end)
    }
}

public enum WeeklyFocusFormatter {
    public static func card(_ snapshot: WeeklyFocusSnapshot) -> String {
        let todos = snapshot.todos.isEmpty
            ? ["(none)"]
            : snapshot.todos.enumerated().map { index, todo in "\(index + 1). \(todo)" }
        let waiting = snapshot.waiting.isEmpty
            ? ["- (none)"]
            : snapshot.waiting.map { "- \($0)" }
        let capturedLabel = snapshot.capturedCount == 1 ? "item" : "items"

        return ([
            "Weekly Focus",
            "============",
            "",
            "Next items"
        ] + todos + [
            "",
            "Waiting"
        ] + waiting + [
            "",
            "Captured: \(snapshot.capturedCount) unchecked \(capturedLabel)",
            "",
            "Source: \(snapshot.weeklyNotePath)"
        ]).joined(separator: "\n")
    }
}

public enum CmuxFocusLauncher {
    public static let promptEnvironmentName = "WEEKLY_FOCUS_PROMPT"
    public static let copilotCommand =
        "if command -v c >/dev/null 2>&1; then c -i \"$WEEKLY_FOCUS_PROMPT\"; else copilot --allow-all -i \"$WEEKLY_FOCUS_PROMPT\"; fi"
    public static let cmuxCandidates = [
        "/Applications/cmux.app/Contents/Resources/bin/cmux",
        "/opt/homebrew/bin/cmux",
        "/usr/local/bin/cmux"
    ]

    public static func buildPrompt(todo: String) -> String {
        [
            "I want to work on this weekly note TODO item:",
            "",
            todo,
            "",
            "Start in my Brain. Read the current weekly note for context, then help me clarify the next action and work the item end-to-end. Keep the weekly note as the canonical commitment store."
        ].joined(separator: "\n")
    }

    public static func buildCommand(
        todo: String,
        brainRoot: String,
        cmuxPath: String? = nil
    ) -> LaunchCommand {
        let prompt = buildPrompt(todo: todo)
        return LaunchCommand(
            executable: resolveCmuxPath(cmuxPath),
            arguments: [
                "new-workspace",
                "--name",
                workspaceTitle(for: todo),
                "--cwd",
                brainRoot,
                "--env",
                "\(promptEnvironmentName)=\(prompt)",
                "--command",
                copilotCommand,
                "--focus",
                "true"
            ]
        )
    }

    public static func resolveCmuxPath(_ override: String? = nil) -> String {
        if let override, !override.isEmpty {
            return override
        }

        for candidate in cmuxCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return "/usr/bin/env"
    }

    public static func launch(todo: String, brainRoot: String) throws {
        let command = buildCommand(todo: todo, brainRoot: brainRoot)
        let process = Process()

        if command.executable == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = ["cmux"] + command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        }

        try process.run()
    }

    private static func workspaceTitle(for todo: String) -> String {
        let normalized = todo.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count <= 60 {
            return normalized
        }

        return "\(normalized.prefix(57))..."
    }
}
