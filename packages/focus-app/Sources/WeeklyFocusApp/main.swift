import AppKit
import WeeklyFocusCore

private func printFocusAndExit() {
    do {
        let snapshot = try WeeklyFocusReader().read(todoLimit: 5)
        print(WeeklyFocusFormatter.card(snapshot))
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--print-focus") {
    printFocusAndExit()
}

if CommandLine.arguments.contains("--self-test-copilot-launch") {
    let todo = "Weekly Focus Copilot Smoke \(UUID().uuidString)"
    do {
        try CmuxFocusLauncher.launch(
            todo: todo,
            brainRoot: WeeklyFocusReader().brainRoot,
            focus: false
        )
        print(todo)
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let requestedAppearanceName: NSAppearance.Name? = {
    guard let appearanceIndex = CommandLine.arguments.firstIndex(of: "--appearance"),
          CommandLine.arguments.indices.contains(appearanceIndex + 1) else {
        return nil
    }

    return CommandLine.arguments[appearanceIndex + 1] == "dark"
        ? NSAppearance.Name.darkAqua
        : NSAppearance.Name.aqua
}()

enum FocusColors {
    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1)
            : NSColor(red: 0xfe / 255, green: 0xfc / 255, blue: 0xf9 / 255, alpha: 1)
    }

    static let text = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0xc9 / 255, green: 0xd1 / 255, blue: 0xd9 / 255, alpha: 1)
            : NSColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    }

    static let muted = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x8b / 255, green: 0x94 / 255, blue: 0x9e / 255, alpha: 1)
            : NSColor(red: 0x66 / 255, green: 0x66 / 255, blue: 0x66 / 255, alpha: 1)
    }

    static let fieldBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x2d / 255, green: 0x2d / 255, blue: 0x2d / 255, alpha: 1)
            : .white
    }

    static let fieldBorder = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x44 / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
            : NSColor(red: 0xcc / 255, green: 0xcc / 255, blue: 0xcc / 255, alpha: 1)
    }

    static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0xff / 255, green: 0x6b / 255, blue: 0x57 / 255, alpha: 1)
            : NSColor(red: 0xc4 / 255, green: 0x3e / 255, blue: 0x2a / 255, alpha: 1)
    }
}

final class FocusWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

final class FocusRootView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = FocusColors.background.cgColor
        }
    }
}

final class TodoRowButton: NSControl {
    var todoIndex: Int = 0
    private let todoTitle: String

    init(index: Int, title: String) {
        self.todoIndex = index
        self.todoTitle = title
        super.init(frame: .zero)
        toolTip = title
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(index + 1). \(title)")
        setAccessibilityTitle("\(index + 1). \(title)")
        widthAnchor.constraint(equalToConstant: FocusLayout.rowWidth).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height(for: title, index: index)).isActive = true
    }

    required init?(coder: NSCoder) {
        self.todoTitle = ""
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: FocusLayout.rowWidth, height: Self.height(for: todoTitle, index: todoIndex))
    }

    override var isFlipped: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let title = Self.attributedTitle(index: todoIndex, title: todoTitle)
        let textHeight = title.boundingRect(
            with: NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let rect = NSRect(
            x: 0,
            y: Swift.max(0, floor((bounds.height - textHeight) / 2)),
            width: bounds.width,
            height: bounds.height
        )

        title.draw(in: rect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        sendConfiguredAction()
    }

    override func performClick(_ sender: Any?) {
        sendConfiguredAction()
    }

    override func accessibilityPerformPress() -> Bool {
        sendConfiguredAction()
        return true
    }

    private func sendConfiguredAction() {
        guard let action else {
            return
        }

        NSApp.sendAction(action, to: target, from: self)
    }

    static func height(for title: String, index: Int) -> CGFloat {
        let font = FocusFonts.todo(index: index)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle(index: index, font: font)
        ]
        let rect = NSString(string: "\(index + 1). \(title)").boundingRect(
            with: NSSize(width: FocusLayout.rowWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return max(42, ceil(rect.height) + 6)
    }

    private static func attributedTitle(index: Int, title: String) -> NSAttributedString {
        let font = FocusFonts.todo(index: index)
        return NSAttributedString(
            string: "\(index + 1). \(title)",
            attributes: [
                .font: font,
                .foregroundColor: FocusColors.text,
                .paragraphStyle: paragraphStyle(index: index, font: font)
            ]
        )
    }

    private static func paragraphStyle(index: Int, font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        style.headIndent = prefixWidth(index: index, font: font)
        return style
    }

    private static func prefixWidth(index: Int, font: NSFont) -> CGFloat {
        NSString(string: "\(index + 1). ").size(withAttributes: [.font: font]).width
    }
}

enum FocusLayout {
    static let numberWidth: CGFloat = 44
    static let columnGap: CGFloat = 12
    static let bodyWidth: CGFloat = 940
    static let rowWidth: CGFloat = numberWidth + columnGap + bodyWidth
}

enum FocusFonts {
    static func todo(index: Int) -> NSFont {
        named("Avenir Next", size: index == 0 ? 30 : 28, weight: index == 0 ? .semibold : .medium)
    }

    static func overflow(index: Int) -> NSFont {
        named("Avenir Next", size: CGFloat(Swift.max(13, 18 - index)), weight: .regular)
    }

    static func input() -> NSFont {
        named("Avenir Next", size: 24, weight: .regular)
    }

    private static func named(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var window: NSWindow?
    private var snapshot: WeeklyFocusSnapshot?
    private var keyMonitor: Any?
    private var isSubmittingTodo = false
    private let selfTestMode = CommandLine.arguments.contains("--self-test")
    private let selfTestLaunchMode = CommandLine.arguments.contains("--self-test-launch")
    private let contentStack = NSStackView()
    private let captureField = NSTextField()

    private var primaryTextColor: NSColor {
        FocusColors.text
    }

    private var secondaryTextColor: NSColor {
        FocusColors.muted
    }

    private var launchCommandOverride: String? {
        let value = ProcessInfo.processInfo.environment["WEEKLY_FOCUS_LAUNCH_COMMAND_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value?.isEmpty == false {
            return value
        }

        if selfTestLaunchMode {
            return "printf weekly-focus-launch-ok > /tmp/weekly-focus-app-launch-self-test.txt"
        }

        return nil
    }

    private var shouldFocusLaunchedWorkspace: Bool {
        if selfTestLaunchMode {
            return false
        }

        return ProcessInfo.processInfo.environment["WEEKLY_FOCUS_LAUNCH_FOCUS"] != "false"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createWindow()
        reload()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleKeyDown(event)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if selfTestMode {
            DispatchQueue.main.async {
                self.runSelfTest()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        resizeToCurrentScreen()
    }

    private func createWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = FocusWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "Weekly Focus"
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = FocusColors.background
        window.collectionBehavior = [.canJoinAllSpaces]
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentView = buildRootView(frame: NSRect(origin: .zero, size: frame.size))
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func buildRootView(frame: NSRect) -> NSView {
        let root = FocusRootView(frame: frame)
        root.autoresizingMask = [.width, .height]

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 18
        container.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16

        container.addArrangedSubview(contentStack)
        root.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 72),
            container.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -72),
            container.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: 60),
            container.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -60)
        ])

        return root
    }

    private func reload() {
        do {
            let snapshot = try WeeklyFocusReader().read(todoLimit: 5)
            self.snapshot = snapshot
            render(snapshot: snapshot)
        } catch {
            snapshot = nil
            renderError(error)
        }
    }

    private func render(snapshot: WeeklyFocusSnapshot) {
        clearContent()

        if snapshot.todos.isEmpty {
            contentStack.addArrangedSubview(messageLabel("No TODOs"))
        } else {
            for (index, todo) in snapshot.todos.enumerated() {
                contentStack.addArrangedSubview(todoRow(index: index, title: todo))
            }
        }

        if !snapshot.overflowTodos.isEmpty {
            contentStack.addArrangedSubview(overflowSection(snapshot.overflowTodos))
        }

        contentStack.addArrangedSubview(captureRow())
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.captureField)
        }
    }

    private func renderError(_ error: Error) {
        clearContent()
        contentStack.addArrangedSubview(messageLabel(error.localizedDescription))
    }

    private func clearContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func todoRow(index: Int, title: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .leading
        row.spacing = 0
        row.addArrangedSubview(todoButton(index: index, title: title))
        return row
    }

    private func overflowSection(_ todos: [String]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let shown = Array(todos.prefix(10))
        for (index, todo) in shown.enumerated() {
            stack.addArrangedSubview(overflowLabel(todo, index: index))
        }

        if todos.count > shown.count {
            stack.addArrangedSubview(overflowLabel("… \(todos.count - shown.count) more", index: shown.count))
        }

        return stack
    }

    private func captureRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0

        captureField.placeholderString = ""
        captureField.font = FocusFonts.input()
        captureField.textColor = primaryTextColor
        captureField.backgroundColor = FocusColors.fieldBackground
        captureField.layer?.borderColor = FocusColors.fieldBorder.cgColor
        captureField.focusRingType = .default
        captureField.target = self
        captureField.action = #selector(todoSubmitted(_:))
        captureField.delegate = self
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.widthAnchor.constraint(equalToConstant: FocusLayout.rowWidth).isActive = true

        row.addArrangedSubview(captureField)
        return row
    }

    private func todoButton(index: Int, title: String) -> TodoRowButton {
        let button = TodoRowButton(index: index, title: title)
        button.target = self
        button.action = #selector(todoButtonPressed(_:))
        return button
    }

    private func messageLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = FocusFonts.todo(index: 0)
        label.textColor = primaryTextColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = secondaryTextColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func overflowLabel(_ text: String, index: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = FocusFonts.overflow(index: index)
        let alpha = Swift.max(0.10, 0.38 - (Double(index) * 0.035))
        label.textColor = secondaryTextColor.withAlphaComponent(alpha)
        label.maximumNumberOfLines = 1
        return label
    }

    @objc private func todoButtonPressed(_ sender: TodoRowButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            markDone(at: sender.todoIndex)
        } else {
            launchTodo(at: sender.todoIndex)
        }
    }

    @objc private func todoSubmitted(_ sender: Any) {
        submitTodo()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let movement = (obj.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        if movement == NSReturnTextMovement {
            submitTodo()
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if control === captureField && commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submitTodo()
            return true
        }

        return false
    }

    private func submitTodo() {
        if isSubmittingTodo {
            return
        }

        let text = captureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        guard let snapshot else {
            return
        }

        do {
            isSubmittingTodo = true
            try WeeklyFocusReader.appendTodo(
                text,
                weeklyNotePath: snapshot.weeklyNotePath
            )
            captureField.stringValue = ""
            window?.makeFirstResponder(nil)
            reload()
            isSubmittingTodo = false
        } catch {
            isSubmittingTodo = false
            showAlert(title: "Could not capture", message: error.localizedDescription)
        }
    }

    private func launchTodo(at index: Int) {
        do {
            try startTodo(at: index)
        } catch {
            showAlert(title: "Could not open cmux", message: error.localizedDescription)
        }
    }

    private func startTodo(at index: Int) throws {
        guard let snapshot, snapshot.todos.indices.contains(index) else {
            return
        }

        try CmuxFocusLauncher.launch(
            todo: snapshot.todos[index],
            commandOverride: launchCommandOverride,
            focus: shouldFocusLaunchedWorkspace
        )
    }

    private func markDone(at index: Int) {
        guard let snapshot, snapshot.todos.indices.contains(index) else {
            return
        }

        do {
            try WeeklyFocusReader.markTodoDone(
                snapshot.todos[index],
                weeklyNotePath: snapshot.weeklyNotePath
            )
            reload()
        } catch {
            showAlert(title: "Could not mark TODO done", message: error.localizedDescription)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }

        if event.modifierFlags.contains(.command),
           let number = Int(characters),
           (1...5).contains(number) {
            launchTodo(at: number - 1)
            return nil
        }

        if let firstResponder = window?.firstResponder,
           let editor = captureField.currentEditor(),
           firstResponder === editor {
            if event.keyCode == 36 || event.keyCode == 76 {
                submitTodo()
                return nil
            }

            return event
        }

        if characters == "q" || event.keyCode == 53 {
            NSApp.terminate(nil)
            return nil
        }

        if characters == "r" {
            reload()
            return nil
        }

        if characters == "c" {
            window?.makeFirstResponder(captureField)
            return nil
        }

        if let number = Int(characters), (1...5).contains(number) {
            launchTodo(at: number - 1)
            return nil
        }

        return event
    }

    @objc private func screenParametersDidChange() {
        resizeToCurrentScreen()
    }

    private func resizeToCurrentScreen() {
        guard let window else {
            return
        }

        let frame = window.screen?.frame ?? NSScreen.main?.frame
        if let frame {
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func runSelfTest() {
        do {
            guard let window else {
                throw WeeklyFocusError.launchFailed("self-test window missing")
            }

            guard window.canBecomeKey, window.isKeyWindow || window.makeFirstResponder(captureField) else {
                throw WeeklyFocusError.launchFailed("self-test window cannot focus capture field")
            }

            captureField.stringValue = "Self-test todo"
            todoSubmitted(self)

            guard let afterTodo = snapshot, afterTodo.todos.contains("Self-test todo") else {
                throw WeeklyFocusError.launchFailed("self-test TODO entry did not refresh snapshot")
            }

            let firstTodo = afterTodo.todos.first
            if firstTodo != nil {
                markDone(at: 0)
                let afterDone = try WeeklyFocusReader().read(todoLimit: 5)
                if afterDone.todos.first == firstTodo {
                    throw WeeklyFocusError.launchFailed("self-test mark done did not update TODO list")
                }
            }

            if selfTestLaunchMode {
                let launchFile = "/tmp/weekly-focus-app-launch-self-test.txt"
                try? FileManager.default.removeItem(atPath: launchFile)
                try CmuxFocusLauncher.launch(
                    todo: "Self-test launch",
                    brainRoot: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Brain")
                        .path,
                    commandOverride: launchCommandOverride,
                    focus: shouldFocusLaunchedWorkspace
                )
            }

            if selfTestLaunchMode {
                try startTodo(at: 0)
                let commandOne = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: "1",
                    charactersIgnoringModifiers: "1",
                    isARepeat: false,
                    keyCode: 18
                )
                if let commandOne, handleKeyDown(commandOne) != nil {
                    throw WeeklyFocusError.launchFailed("self-test command-1 was not handled")
                }
            }

            print("weekly-focus self-test ok")
            NSApp.terminate(nil)
        } catch {
            fputs("weekly-focus self-test failed: \(error.localizedDescription)\n", stderr)
            NSApp.terminate(nil)
            exit(1)
        }
    }
}

let app = NSApplication.shared
if let requestedAppearanceName {
    app.appearance = NSAppearance(named: requestedAppearanceName)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
