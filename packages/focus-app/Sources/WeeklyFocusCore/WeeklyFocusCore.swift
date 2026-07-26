import Foundation
import Darwin

public struct WeeklyFocusSnapshot: Equatable, Sendable {
    public let brainRoot: String
    public let weeklyNotePath: String

    /// The focus list itself. Board tasks are the only representation; the string
    /// views below exist because the renderer and the printed card want text.
    public let tasks: [FocusTask]

    /// Open tasks behind the focus list, shown dimmed.
    public let overflowTasks: [FocusTask]

    /// Tasks parked on someone else.
    public let waitingTasks: [FocusTask]

    /// Tasks already closed in the current week.
    public let capturedCount: Int

    public var todos: [String] {
        tasks.map(\.displayText)
    }

    public var overflowTodos: [String] {
        overflowTasks.map(\.displayText)
    }

    public var waiting: [String] {
        waitingTasks.map(\.displayText)
    }

    public var now: String? {
        todos.first
    }

    public var next: String? {
        todos.dropFirst().first
    }

    public init(
        brainRoot: String,
        weeklyNotePath: String,
        tasks: [FocusTask] = [],
        overflowTasks: [FocusTask] = [],
        waitingTasks: [FocusTask] = [],
        capturedCount: Int = 0
    ) {
        self.brainRoot = brainRoot
        self.weeklyNotePath = weeklyNotePath
        self.tasks = tasks
        self.overflowTasks = overflowTasks
        self.waitingTasks = waitingTasks
        self.capturedCount = capturedCount
    }

    /// Splits board items into the focus list, the overflow behind it, and waiting.
    public static func fromBoard(
        _ boardTasks: [FocusTask],
        brainRoot: String,
        weeklyNotePath: String,
        todoLimit: Int = 5,
        overflowLimit: Int? = nil,
        waitingLimit: Int = 3
    ) -> WeeklyFocusSnapshot {
        let ordered = focusOrdered(boardTasks)
        let open = ordered.filter { $0.isOpen && !$0.isWaiting }
        let waiting = ordered.filter(\.isWaiting)

        let focused = Array(open.prefix(Swift.max(0, todoLimit)))
        var overflow = Array(open.dropFirst(Swift.max(0, todoLimit)))
        if let overflowLimit {
            overflow = Array(overflow.prefix(Swift.max(0, overflowLimit)))
        }

        return WeeklyFocusSnapshot(
            brainRoot: brainRoot,
            weeklyNotePath: weeklyNotePath,
            tasks: focused,
            overflowTasks: overflow,
            waitingTasks: Array(waiting.prefix(Swift.max(0, waitingLimit))),
            capturedCount: boardTasks.filter { !$0.isOpen }.count
        )
    }
}

public struct LaunchCommand: Equatable {
    public let executable: String
    public let arguments: [String]
}

public enum WeeklyFocusError: LocalizedError {
    case launchFailed(String)
    case todoNotFound(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .todoNotFound(let todo):
            return "Task not found on the board: \(todo)"
        case .writeFailed(let message):
            return message
        }
    }
}

public struct BrainWikilink: Equatable {
    public let target: String
    public let displayText: String
    public let range: NSRange
}

public enum WeeklyFocusTodoAction: Equatable {
    case launchCopilot
    case copySessionID(String)
    case openURL(URL)
    case openBrainWikilink(String)
}

public enum WeeklyFocusTodoActionResolver {
    private static let sessionIDPattern =
        #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    private static let urlPattern = #"https?://[^\s)\]]+"#
    private static let trailingURLPunctuation = CharacterSet(charactersIn: ".,;:!?>}\"'")

    private struct TextMatch {
        let text: String
        let range: NSRange
    }

    public static func resolve(_ todo: String) -> WeeklyFocusTodoAction {
        let urlMatches = matches(in: todo, pattern: urlPattern)
        let sessionMatches = matches(in: todo, pattern: sessionIDPattern)
        if let sessionMatch = sessionMatches.first(where: { sessionMatch in
            !urlMatches.contains(where: { urlMatch in
                NSLocationInRange(sessionMatch.range.location, urlMatch.range) &&
                    NSMaxRange(sessionMatch.range) <= NSMaxRange(urlMatch.range)
            })
        }) {
            return .copySessionID(sessionMatch.text)
        }

        if let rawURL = urlMatches.first?.text,
           let urlText = rawURL.trimmingCharacters(in: trailingURLPunctuation).nonEmpty,
           let url = URL(string: urlText) {
            return .openURL(url)
        }

        if let wikilink = BrainWikilinkResolver.wikilinks(in: todo).first {
            return .openBrainWikilink(wikilink.target)
        }

        return .launchCopilot
    }

    private static func matches(in text: String, pattern: String) -> [TextMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = NSString(string: text)
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            TextMatch(text: nsText.substring(with: match.range), range: match.range)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

public enum BrainWikilinkResolver {
    private static let pattern = #"\[\[([^\]\|\n]+)(?:\|([^\]\n]+))?\]\]"#

    public static func wikilinks(in text: String) -> [BrainWikilink] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsText = NSString(string: text)
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 2 else {
                return nil
            }

            let target = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else {
                return nil
            }

            let displayText: String
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                displayText = nsText.substring(with: match.range(at: 2))
            } else {
                displayText = target
            }

            return BrainWikilink(target: target, displayText: displayText, range: match.range)
        }
    }

    public static func resolvePath(target: String, brainRoot: String) -> String? {
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return nil
        }

        let resolvedBrainRoot = URL(fileURLWithPath: BrainPaths.resolveHome(brainRoot))
            .standardizedFileURL

        if target.hasPrefix("uid:") {
            let uid = String(target.dropFirst("uid:".count))
                .split(separator: "#", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !uid.isEmpty else {
                return nil
            }

            return resolveUID(uid, brainRootURL: resolvedBrainRoot)
        }

        guard !target.hasPrefix("/") else {
            return nil
        }

        let targetPath = target
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !targetPath.isEmpty else {
            return nil
        }

        let candidate = resolvedBrainRoot.appendingPathComponent(targetPath)
        return firstExistingPath(
            candidates: [
                candidate,
                candidate.pathExtension.isEmpty ? candidate.appendingPathExtension("md") : candidate
            ],
            brainRootURL: resolvedBrainRoot
        )
    }

    private static func firstExistingPath(candidates: [URL], brainRootURL: URL) -> String? {
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard isWithinBrain(standardized, brainRootURL: brainRootURL) else {
                continue
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return standardized.path
            }
        }

        return nil
    }

    private static func resolveUID(_ uid: String, brainRootURL: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: brainRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else {
                continue
            }

            let standardized = url.standardizedFileURL
            guard isWithinBrain(standardized, brainRootURL: brainRootURL),
                  let content = try? String(contentsOf: standardized, encoding: .utf8) else {
                continue
            }

            let escapedUID = NSRegularExpression.escapedPattern(for: uid)
            if content.range(of: #"(?m)^uid:\s*\#(escapedUID)\s*$"#, options: .regularExpression) != nil {
                return standardized.path
            }
        }

        return nil
    }

    private static func isWithinBrain(_ url: URL, brainRootURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = brainRootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix("\(rootPath)/")
    }
}

/// Locates the Brain root and the current weekly note.
///
/// Tasks live on the board, so nothing here reads or writes task state. The app still
/// needs these paths to open the weekly note and to resolve Brain wikilinks that
/// appear in task text.
public struct BrainPaths {
    public let brainRoot: String
    public let weeklyNotePath: String

    public init(
        brainRoot: String = BrainPaths.defaultBrainRoot(),
        date: Date = Date(),
        weeklyNotePath: String? = nil,
        calendar: Calendar = .current
    ) {
        let resolvedBrainRoot = BrainPaths.resolveHome(brainRoot)
        self.brainRoot = resolvedBrainRoot
        self.weeklyNotePath = weeklyNotePath ?? BrainPaths.currentOrLatestWeeklyNotePath(
            brainRoot: resolvedBrainRoot,
            date: date,
            calendar: calendar
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

    public static func currentOrLatestWeeklyNotePath(
        brainRoot: String,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        let currentPath = weeklyNotePath(
            brainRoot: brainRoot,
            date: date,
            calendar: calendar
        )

        if FileManager.default.fileExists(atPath: currentPath) {
            return currentPath
        }

        guard let latestPath = latestWeeklyNotePath(
            brainRoot: brainRoot,
            beforeOrOn: date,
            calendar: calendar
        ) else {
            return currentPath
        }

        return latestPath
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

    private static func latestWeeklyNotePath(
        brainRoot: String,
        beforeOrOn date: Date,
        calendar: Calendar
    ) -> String? {
        let weeklyNotesDirectory = URL(fileURLWithPath: brainRoot)
            .appendingPathComponent("Weekly Notes")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: weeklyNotesDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let currentWeekStart = startOfWeekSunday(date, calendar: calendar)
        let prefix = "Week of "
        let suffix = ".md"

        let candidates = entries.compactMap { url -> (date: Date, path: String)? in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
                return nil
            }

            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -suffix.count)
            let dateText = String(name[start..<end])
            guard let weekStart = formatter.date(from: dateText),
                  weekStart <= currentWeekStart else {
                return nil
            }

            return (weekStart, url.path)
        }

        return candidates.sorted { $0.date > $1.date }.first?.path
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
            "Source: Brain Tasks board (project \(BrainBoard.projectNumber))"
        ]).joined(separator: "\n")
    }
}

public enum CmuxFocusLauncher {
    public static let promptEnvironmentName = "WEEKLY_FOCUS_PROMPT"
    public static let cmuxCandidates = [
        "/Applications/cmux.app/Contents/Resources/bin/cmux",
        "/opt/homebrew/bin/cmux",
        "/usr/local/bin/cmux"
    ]

    struct WorkspaceCreateResponse: Decodable {
        let workspaceRef: String
        let surfaceRef: String

        enum CodingKeys: String, CodingKey {
            case workspaceRef = "workspace_ref"
            case surfaceRef = "surface_ref"
        }
    }

    struct CmuxRunResult {
        let status: Int32
        let output: String
        let error: String
    }

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
        focus: Bool = true
    ) -> LaunchCommand {
        return LaunchCommand(
            executable: resolveCmuxPath(cmuxPath),
            arguments: [
                "--json",
                "workspace",
                "create",
                "--name",
                workspaceTitle(for: todo),
                "--cwd",
                brainRoot,
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

    @discardableResult
    public static func launch(
        todo: String,
        brainRoot: String = defaultLaunchBrainRoot(),
        cmuxPath: String? = nil,
        commandOverride: String? = nil,
        focus: Bool = true
    ) throws -> String? {
        let launchCommand = try commandOverride ?? buildScriptedCopilotCommand(todo: todo)
        let createCommand = buildCommand(
            todo: todo,
            brainRoot: brainRoot,
            cmuxPath: cmuxPath,
            focus: focus
        )

        let createResult = try runCmux(createCommand)
        guard createResult.status == 0 else {
            throw WeeklyFocusError.launchFailed(failureMessage(
                prefix: "cmux workspace create exited with \(createResult.status)",
                result: createResult
            ))
        }

        let response = try parseWorkspaceCreateResponse(createResult.output)
        try waitForSurfaceReady(
            workspaceRef: response.workspaceRef,
            surfaceRef: response.surfaceRef,
            cmuxPath: createCommand.executable
        )
        try sendCommand(
            launchCommand,
            workspaceRef: response.workspaceRef,
            surfaceRef: response.surfaceRef,
            cmuxPath: createCommand.executable
        )

        if focus {
            try selectWorkspace(response.workspaceRef, cmuxPath: createCommand.executable)
        }

        return response.workspaceRef
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

        return "zsh -lic \(shellQuote("source \(shellQuote(scriptPath.path))"))"
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

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func parseWorkspaceCreateResponse(_ output: String) throws -> WorkspaceCreateResponse {
        guard let data = output.data(using: .utf8) else {
            throw WeeklyFocusError.launchFailed("cmux workspace create returned non-UTF8 output")
        }

        do {
            return try JSONDecoder().decode(WorkspaceCreateResponse.self, from: data)
        } catch {
            throw WeeklyFocusError.launchFailed("cmux workspace create returned unexpected output: \(output)")
        }
    }

    private static func waitForSurfaceReady(
        workspaceRef: String,
        surfaceRef: String,
        cmuxPath: String,
        timeout: TimeInterval = 10
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError = ""

        repeat {
            let result = try runCmux(
                executable: cmuxPath,
                arguments: [
                    "read-screen",
                    "--workspace",
                    workspaceRef,
                    "--surface",
                    surfaceRef,
                    "--lines",
                    "5"
                ]
            )

            if result.status == 0 {
                return
            }

            lastError = failureMessage(
                prefix: "cmux read-screen exited with \(result.status)",
                result: result
            )
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        throw WeeklyFocusError.launchFailed("cmux terminal surface was not ready: \(lastError)")
    }

    private static func sendCommand(
        _ command: String,
        workspaceRef: String,
        surfaceRef: String,
        cmuxPath: String
    ) throws {
        let result = try runCmux(
            executable: cmuxPath,
            arguments: [
                "send",
                "--workspace",
                workspaceRef,
                "--surface",
                surfaceRef,
                "\(command)\\n"
            ]
        )

        guard result.status == 0 else {
            throw WeeklyFocusError.launchFailed(failureMessage(
                prefix: "cmux send exited with \(result.status)",
                result: result
            ))
        }
    }

    private static func selectWorkspace(_ workspaceRef: String, cmuxPath: String) throws {
        let result = try runCmux(
            executable: cmuxPath,
            arguments: ["workspace", "select", workspaceRef]
        )

        guard result.status == 0 else {
            throw WeeklyFocusError.launchFailed(failureMessage(
                prefix: "cmux workspace select exited with \(result.status)",
                result: result
            ))
        }
    }

    private static func runCmux(_ command: LaunchCommand) throws -> CmuxRunResult {
        try runCmux(executable: command.executable, arguments: command.arguments)
    }

    private static func runCmux(
        executable: String,
        arguments: [String]
    ) throws -> CmuxRunResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        if executable == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["cmux"] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }
        process.environment = cmuxProcessEnvironment()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return CmuxRunResult(
            status: process.terminationStatus,
            output: String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            error: String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func failureMessage(prefix: String, result: CmuxRunResult) -> String {
        let details = [result.error, result.output]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return details.isEmpty ? prefix : "\(prefix)\n\(details)"
    }

    static func cmuxProcessEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var sanitized = environment.filter { key, _ in
            !key.hasPrefix("CMUX_")
        }

        if let password = environment["CMUX_SOCKET_PASSWORD"] {
            sanitized["CMUX_SOCKET_PASSWORD"] = password
        }

        return sanitized
    }
}
