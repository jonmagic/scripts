import Foundation
import Darwin

public struct WeeklyFocusSnapshot: Equatable {
    public let brainRoot: String
    public let weeklyNotePath: String
    public let todos: [String]
    public let overflowTodos: [String]
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
        overflowTodos: [String] = [],
        waiting: [String],
        capturedCount: Int
    ) {
        self.brainRoot = brainRoot
        self.weeklyNotePath = weeklyNotePath
        self.todos = todos
        self.overflowTodos = overflowTodos
        self.waiting = waiting
        self.capturedCount = capturedCount
    }
}

public struct LaunchCommand: Equatable {
    public let executable: String
    public let arguments: [String]
}

public enum WeeklyFocusError: LocalizedError {
    case launchFailed(String)
    case todoNotFound(String)
    case weeklyNoteMissing(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .todoNotFound(let todo):
            return "TODO not found in weekly note: \(todo)"
        case .weeklyNoteMissing(let path):
            return "Weekly note not found: \(path)"
        case .writeFailed(let path):
            return "Could not update weekly note: \(path)"
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

    @discardableResult
    public static func markTodoDone(
        _ todo: String,
        weeklyNotePath: String
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: weeklyNotePath) else {
            throw WeeklyFocusError.weeklyNoteMissing(weeklyNotePath)
        }

        let content = try String(contentsOfFile: weeklyNotePath, encoding: .utf8)
        var lines = content.components(separatedBy: .newlines)

        guard let bounds = sectionBounds(in: lines, heading: "## TODO") else {
            throw WeeklyFocusError.todoNotFound(todo)
        }

        for index in bounds.start..<bounds.end {
            let line = lines[index]
            guard line.hasPrefix("- [ ] ") else {
                continue
            }

            let item = String(line.dropFirst("- [ ] ".count)).trimmingCharacters(in: .whitespaces)
            guard item == todo else {
                continue
            }

            let originalItem = String(line.dropFirst("- [ ] ".count))
            lines[index] = "- [x] \(originalItem)"
            try writeFileAtomically(lines.joined(separator: "\n"), to: weeklyNotePath)
            return true
        }

        throw WeeklyFocusError.todoNotFound(todo)
    }

    @discardableResult
    public static func appendCapture(
        _ text: String,
        weeklyNotePath: String,
        source: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: weeklyNotePath) else {
            throw WeeklyFocusError.weeklyNoteMissing(weeklyNotePath)
        }

        let normalizedText = normalizeSingleLine(text)
        guard !normalizedText.isEmpty else {
            throw WeeklyFocusError.writeFailed("Capture text is required")
        }

        let normalizedSource = source.map { normalizeSingleLine($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let line = captureLine(text: normalizedText, source: normalizedSource, now: now, calendar: calendar)
        let content = try String(contentsOfFile: weeklyNotePath, encoding: .utf8)
        var lines = content.components(separatedBy: .newlines)

        if let captured = sectionBounds(in: lines, heading: "## Captured") {
            insertBeforeSectionTrailingBlank(&lines, sectionStart: captured.start, sectionEnd: captured.end, line: line)
        } else {
            let insertionIndex = sectionBounds(in: lines, heading: "## TODO")?.end ?? lines.count
            insertNewSection(&lines, before: insertionIndex, heading: "## Captured", firstLine: line)
        }

        try writeFileAtomically(lines.joined(separator: "\n"), to: weeklyNotePath)
        return line
    }

    @discardableResult
    public static func appendTodo(
        _ text: String,
        weeklyNotePath: String
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: weeklyNotePath) else {
            throw WeeklyFocusError.weeklyNoteMissing(weeklyNotePath)
        }

        let normalizedText = normalizeSingleLine(text)
        guard !normalizedText.isEmpty else {
            throw WeeklyFocusError.writeFailed("TODO text is required")
        }

        let line = "- [ ] \(normalizedText)"
        let content = try String(contentsOfFile: weeklyNotePath, encoding: .utf8)
        var lines = content.components(separatedBy: .newlines)

        if let todo = sectionBounds(in: lines, heading: "## TODO") {
            insertBeforeSectionTrailingBlank(&lines, sectionStart: todo.start, sectionEnd: todo.end, line: line)
        } else {
            insertNewSection(&lines, before: lines.count, heading: "## TODO", firstLine: line)
        }

        try writeFileAtomically(lines.joined(separator: "\n"), to: weeklyNotePath)
        return line
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
        let limit = Swift.max(0, todoLimit)
        let todos = Array(todoItems[..<Swift.min(todoItems.count, limit)])
        let overflowTodos = todoItems.count > limit ? Array(todoItems[limit...]) : []
        let waiting = Array(waitingItems[..<Swift.min(waitingItems.count, Swift.max(0, waitingLimit))])
        let capturedCount = uncheckedItems(in: lines, heading: "## Captured").count

        return WeeklyFocusSnapshot(
            brainRoot: brainRoot,
            weeklyNotePath: weeklyNotePath,
            todos: todos,
            overflowTodos: overflowTodos,
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

    private static func captureLine(
        text: String,
        source: String?,
        now: Date,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: now)

        if let source {
            return "- [ ] \(timestamp) \(text) (source: \(source))"
        }

        return "- [ ] \(timestamp) \(text)"
    }

    private static func normalizeSingleLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sectionBounds(in lines: [String], heading: String) -> (start: Int, end: Int)? {
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
            return nil
        }

        let start = headingIndex + 1
        let end = lines[start...].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.count
        return (start, end)
    }

    private static func insertBeforeSectionTrailingBlank(
        _ lines: inout [String],
        sectionStart: Int,
        sectionEnd: Int,
        line: String
    ) {
        var insertionIndex = sectionEnd

        while insertionIndex > sectionStart + 1 && lines[insertionIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertionIndex -= 1
        }

        lines.insert(line, at: insertionIndex)
    }

    private static func insertNewSection(
        _ lines: inout [String],
        before index: Int,
        heading: String,
        firstLine: String
    ) {
        var insertionIndex = index

        while insertionIndex > 0 && lines[insertionIndex - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertionIndex -= 1
        }

        let removedBlankCount = index - insertionIndex
        lines.replaceSubrange(insertionIndex..<index, with: Array(repeating: "", count: 0))
        if removedBlankCount > 0 {
            lines.insert("", at: insertionIndex)
            insertionIndex += 1
        } else if insertionIndex > 0 {
            lines.insert("", at: insertionIndex)
            insertionIndex += 1
        }

        lines.insert(contentsOf: [heading, firstLine, ""], at: insertionIndex)
    }

    private static func writeFileAtomically(_ content: String, to path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".\(URL(fileURLWithPath: path).lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).tmp")

        try content.write(to: tempURL, atomically: false, encoding: .utf8)
        if rename(tempURL.path, path) != 0 {
            try? FileManager.default.removeItem(at: tempURL)
            throw WeeklyFocusError.writeFailed(path)
        }
    }
}

public enum WeeklyFocusFormatter {
    public static func card(_ snapshot: WeeklyFocusSnapshot) -> String {
        let todos = snapshot.todos.isEmpty
            ? ["(none)"]
            : snapshot.todos.enumerated().map { index, todo in "\(index + 1). \(todo)" }
        let overflow = snapshot.overflowTodos.isEmpty
            ? []
            : ["", "Fading below focus"] + snapshot.overflowTodos.map { "· \($0)" }
        let waiting = snapshot.waiting.isEmpty
            ? ["- (none)"]
            : snapshot.waiting.map { "- \($0)" }
        let capturedLabel = snapshot.capturedCount == 1 ? "item" : "items"

        return ([
            "Weekly Focus",
            "============",
            "",
            "Next items"
        ] + todos + overflow + [
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
        "zsh -lic 'source \"$WEEKLY_FOCUS_SCRIPT\"'"
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
        cmuxPath: String? = nil,
        commandOverride: String? = nil,
        focus: Bool = true
    ) -> LaunchCommand {
        return LaunchCommand(
            executable: resolveCmuxPath(cmuxPath),
            arguments: [
                "workspace",
                "create",
                "--name",
                workspaceTitle(for: todo),
                "--cwd",
                brainRoot,
                "--command",
                commandOverride ?? copilotCommand,
                "--focus",
                focus ? "true" : "false"
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

    public static func launch(
        todo: String,
        brainRoot: String = defaultLaunchBrainRoot(),
        commandOverride: String? = nil,
        focus: Bool = true
    ) throws {
        let commandText = try commandOverride ?? buildScriptedCopilotCommand(todo: todo)
        let command = buildCommand(
            todo: todo,
            brainRoot: brainRoot,
            commandOverride: commandText,
            focus: focus
        )
        let process = Process()
        let errorPipe = Pipe()

        if command.executable == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = ["cmux"] + command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        }
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if errorMessage?.contains("Broken pipe") == true && didLikelyCreateWorkspace(title: workspaceTitle(for: todo)) {
                return
            }

            if !didLikelyCreateWorkspace(title: workspaceTitle(for: todo)) {
                throw WeeklyFocusError.launchFailed(errorMessage?.isEmpty == false ? errorMessage! : "cmux exited with \(process.terminationStatus)")
            }
        }
    }

    static func buildScriptedCopilotCommand(todo: String) throws -> String {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("weekly-focus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        let promptPath = tempDirectory.appendingPathComponent("prompt.txt")
        let scriptPath = tempDirectory.appendingPathComponent("launch.zsh")
        try buildPrompt(todo: todo).write(to: promptPath, atomically: true, encoding: .utf8)
        try [
            "cleanup() { rm -rf \(shellQuote(tempDirectory.path)); }",
            "trap cleanup EXIT",
            "prompt=$(cat \(shellQuote(promptPath.path)))",
            "if ! alias c >/dev/null 2>&1; then",
            "  print -u2 'c alias is not available in zsh -lic'",
            "  exit 127",
            "fi",
            "c -i \"$prompt\"",
            ""
        ].joined(separator: "\n").write(to: scriptPath, atomically: true, encoding: .utf8)

        return "WEEKLY_FOCUS_SCRIPT=\(shellQuote(scriptPath.path)) \(copilotCommand)"
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

    public static func defaultLaunchBrainRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Brain")
            .path
    }

    private static func didLikelyCreateWorkspace(title: String) -> Bool {
        let command = buildCommand(
            todo: "list",
            brainRoot: defaultLaunchBrainRoot(),
            commandOverride: "true",
            focus: false
        )
        let process = Process()
        let outputPipe = Pipe()

        if command.executable == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = ["cmux", "workspace", "list"]
        } else {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = ["workspace", "list"]
        }
        process.standardOutput = outputPipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains(title) || output.contains(String(title.prefix(57)))
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
