import AppKit
import Darwin
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

@MainActor
private protocol FocusCommandHandling: AnyObject {
    func handleCommandKeyEquivalent(_ event: NSEvent) -> Bool
}

final class FocusWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let handler = NSApp.delegate as? FocusCommandHandling,
           handler.handleCommandKeyEquivalent(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
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

final class WeeklyNoteWatcher {
    private let path: String
    private let onChange: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "weekly-focus.weekly-note-watcher")
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    init(path: String, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
        watchFile()
        watchDirectory()
    }

    deinit {
        stop()
    }

    func stop() {
        pendingReload?.cancel()
        fileSource?.cancel()
        directorySource?.cancel()
        pendingReload = nil
        fileSource = nil
        directorySource = nil
    }

    private func watchFile() {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .link, .rename, .revoke, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        fileSource = source
    }

    private func watchDirectory() {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let descriptor = open(directory, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.delete, .rename, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        directorySource = source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.rewatchFile()
            let callback = self.onChange
            Task { @MainActor in
                callback()
            }
        }
        pendingReload = work
        queue.asyncAfter(deadline: .now() + 0.20, execute: work)
    }

    private func rewatchFile() {
        fileSource?.cancel()
        fileSource = nil
        watchFile()
    }
}

final class TodoRowButton: NSControl {
    var todoIndex: Int = 0
    var isLaunching = false {
        didSet {
            needsDisplay = true
        }
    }
    private var isHovering = false {
        didSet {
            needsDisplay = true
        }
    }
    private var isPressed = false {
        didSet {
            needsDisplay = true
        }
    }
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

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isLaunching || isPressed || isHovering {
            let highlightRect = bounds.insetBy(dx: -10, dy: 0)
            let alpha = isLaunching ? 0.12 : isPressed ? 0.10 : 0.045
            FocusColors.accent.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 12, yRadius: 12).fill()

            FocusColors.accent.withAlphaComponent(isLaunching || isPressed ? 1 : 0.45).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: -10, y: 5, width: 4, height: bounds.height - 10),
                xRadius: 2,
                yRadius: 2
            ).fill()
        }

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
        isPressed = true
        displayIfNeeded()
        guard let window else {
            isPressed = false
            return
        }

        while true {
            guard let nextEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date.distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            let point = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(point)
            isPressed = isInside
            displayIfNeeded()

            if nextEvent.type == .leftMouseUp {
                if isInside {
                    showLaunchFeedback()
                    DispatchQueue.main.async { [weak self] in
                        self?.sendConfiguredAction()
                    }
                }
                return
            }
        }
    }

    override func performClick(_ sender: Any?) {
        sendConfiguredAction()
    }

    override func accessibilityPerformPress() -> Bool {
        sendConfiguredAction()
        return true
    }

    func showLaunchFeedback() {
        isLaunching = true
        displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isLaunching = false
        }
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation, FocusCommandHandling {
    private var window: NSWindow?
    private var snapshot: WeeklyFocusSnapshot?
    private var keyMonitor: Any?
    private var weeklyNoteWatcher: WeeklyNoteWatcher?
    private var weeklyNotePollTimer: Timer?
    private var watchedWeeklyNotePath: String?
    private var watchedWeeklyNoteContent: String?
    private var todoButtons: [TodoRowButton] = []
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
        configureMenu()
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
        weeklyNoteWatcher?.stop()
        weeklyNotePollTimer?.invalidate()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        resizeToCurrentScreen()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(captureField)
        return true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openTodoMenuItem(_:)) {
            return snapshot?.todos.indices.contains(menuItem.tag) == true
        }

        return true
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Weekly Focus")
        let quitItem = NSMenuItem(
            title: "Quit Weekly Focus",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let focusMenuItem = NSMenuItem()
        let focusMenu = NSMenu(title: "Focus")
        for index in 0..<5 {
            let item = NSMenuItem(
                title: "Open Item \(index + 1)",
                action: #selector(openTodoMenuItem(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.keyEquivalentModifierMask = [.command]
            item.tag = index
            item.target = self
            focusMenu.addItem(item)
        }
        focusMenuItem.submenu = focusMenu
        mainMenu.addItem(focusMenuItem)
        NSApp.mainMenu = mainMenu
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
            watchWeeklyNote(at: snapshot.weeklyNotePath)
            render(snapshot: snapshot)
        } catch {
            snapshot = nil
            renderError(error)
        }
    }

    private func watchWeeklyNote(at path: String) {
        watchedWeeklyNoteContent = weeklyNoteContent(path)
        guard watchedWeeklyNotePath != path else {
            return
        }

        weeklyNoteWatcher?.stop()
        weeklyNotePollTimer?.invalidate()
        watchedWeeklyNotePath = path
        weeklyNoteWatcher = WeeklyNoteWatcher(path: path) { [weak self] in
            self?.reload()
        }
        weeklyNotePollTimer = Timer.scheduledTimer(
            withTimeInterval: 0.50,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadIfWeeklyNoteChanged()
            }
        }
    }

    private func reloadIfWeeklyNoteChanged() {
        guard let path = watchedWeeklyNotePath,
              let content = weeklyNoteContent(path) else {
            return
        }

        guard content != watchedWeeklyNoteContent else {
            return
        }

        watchedWeeklyNoteContent = content
        reload()
    }

    private func weeklyNoteContent(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
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
        todoButtons = []
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
        todoButtons.append(button)
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

    @objc private func openTodoMenuItem(_ sender: NSMenuItem) {
        launchTodo(at: sender.tag)
    }

    @objc private func quit(_ sender: Any) {
        NSApp.terminate(nil)
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
        showLaunchFeedback(at: index)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            do {
                try self.startTodo(at: index)
                self.activateCmux()
            } catch {
                self.showAlert(title: "Could not open cmux", message: error.localizedDescription)
            }
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

    private func showLaunchFeedback(at index: Int) {
        guard todoButtons.indices.contains(index) else {
            return
        }

        todoButtons[index].showLaunchFeedback()
    }

    private func activateCmux() {
        guard shouldFocusLaunchedWorkspace else {
            return
        }

        if let app = NSWorkspace.shared.runningApplications.first(where: { application in
            if application.bundleURL?.lastPathComponent == "cmux.app" {
                return true
            }

            return application.localizedName?.lowercased().contains("cmux") == true
        }) {
            app.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.hide(nil)
            }
            return
        }

        let cmuxURL = URL(fileURLWithPath: "/Applications/cmux.app")
        if FileManager.default.fileExists(atPath: cmuxURL.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: cmuxURL,
                configuration: configuration
            ) { app, _ in
                app?.activate(options: [.activateAllWindows])
                DispatchQueue.main.async {
                    NSApp.hide(nil)
                }
            }
        }
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
        if handleCommandKeyEquivalent(event) {
            return nil
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return event
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

    func handleCommandKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        if let number = Int(characters), (1...5).contains(number) {
            launchTodo(at: number - 1)
            return true
        }

        if characters == "q" {
            NSApp.terminate(nil)
            return true
        }

        return false
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

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            reloadIfWeeklyNoteChanged()
            if condition() {
                return true
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return condition()
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

            if let externallyEditedTodo = afterTodo.todos.first {
                try WeeklyFocusReader.markTodoDone(
                    externallyEditedTodo,
                    weeklyNotePath: afterTodo.weeklyNotePath
                )
                let reloaded = waitUntil(timeout: 3) {
                    self.snapshot?.todos.first != externallyEditedTodo
                }
                if !reloaded {
                    throw WeeklyFocusError.launchFailed("self-test external weekly note edit did not refresh snapshot")
                }
            }

            let firstTodo = snapshot?.todos.first
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
