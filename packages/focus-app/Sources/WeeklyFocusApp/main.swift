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
            focus: true
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

    static let link = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x92 / 255, green: 0x9b / 255, blue: 0xa5 / 255, alpha: 1)
            : NSColor(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)
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
    private weak var scalableContentView: NSView?

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

    func setScalableContentView(_ view: NSView) {
        scalableContentView?.removeFromSuperview()
        scalableContentView = view
        addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let contentView = scalableContentView else {
            return
        }

        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()

        let contentSize = measuredSize(of: contentView)
        let availableBounds = availableContentBounds
        contentView.frame = NSRect(
            x: availableBounds.midX - (contentSize.width / 2),
            y: availableBounds.midY - (contentSize.height / 2),
            width: contentSize.width,
            height: contentSize.height
        )
        contentView.layoutSubtreeIfNeeded()
    }

    private func measuredSize(of view: NSView) -> NSSize {
        guard let stack = view as? NSStackView,
              stack.orientation == .vertical else {
            return view.fittingSize
        }

        let arrangedSubviews = stack.arrangedSubviews.filter { !$0.isHidden }
        let sizes = arrangedSubviews.map(\.fittingSize)
        return NSSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +)
                + (CGFloat(Swift.max(0, sizes.count - 1)) * stack.spacing)
        )
    }

    private var safeContentBounds: NSRect {
        guard let window,
              let screen = window.screen else {
            return bounds
        }

        let visibleWindowRect = window.convertFromScreen(screen.visibleFrame)
        return bounds.intersection(convert(visibleWindowRect, from: nil))
    }

    var availableContentSize: NSSize {
        availableContentBounds.size
    }

    private var availableContentBounds: NSRect {
        safeContentBounds.insetBy(dx: 48, dy: 32)
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
    var completionHandler: (() -> Void)?
    var isActivating = false {
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
    private var isCompletionPressed = false {
        didSet {
            needsDisplay = true
        }
    }
    private let todoTitle: String
    private let layoutScale: CGFloat

    init(index: Int, title: String, scale: CGFloat) {
        self.todoIndex = index
        self.todoTitle = title
        self.layoutScale = scale
        super.init(frame: .zero)
        toolTip = title
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(index + 1). \(title)")
        setAccessibilityTitle("\(index + 1). \(title)")
        widthAnchor.constraint(equalToConstant: FocusLayout.rowWidth(scale: scale)).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height(for: title, index: index, scale: scale)).isActive = true
    }

    required init?(coder: NSCoder) {
        self.todoTitle = ""
        self.layoutScale = 1
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: FocusLayout.rowWidth(scale: layoutScale),
            height: Self.height(for: todoTitle, index: todoIndex, scale: layoutScale)
        )
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
        isCompletionPressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isActivating || isPressed || isHovering {
            let highlightRect = bounds.insetBy(dx: -10, dy: 0)
            let alpha = isActivating ? 0.12 : isPressed ? 0.10 : 0.045
            FocusColors.accent.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 12, yRadius: 12).fill()
        }

        let title = Self.attributedTitle(index: todoIndex, title: todoTitle, scale: layoutScale)
        let textHeight = title.boundingRect(
            with: NSSize(width: Self.textWidth(scale: layoutScale), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        let rect = NSRect(
            x: 0,
            y: Swift.max(0, floor((bounds.height - textHeight) / 2)),
            width: Self.textWidth(scale: layoutScale),
            height: bounds.height
        )

        title.draw(in: rect)
        if isHovering || isCompletionPressed {
            drawCompletionCheckbox()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let initialPoint = convert(event.locationInWindow, from: nil)
        let isCompleting = completionRect.contains(initialPoint)
        isCompletionPressed = isCompleting
        isPressed = !isCompleting
        displayIfNeeded()
        guard let window else {
            isPressed = false
            isCompletionPressed = false
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
            let isInside = isCompleting
                ? completionRect.contains(point)
                : bounds.contains(point) && !completionRect.contains(point)
            isCompletionPressed = isCompleting && isInside
            isPressed = !isCompleting && isInside
            displayIfNeeded()

            if nextEvent.type == .leftMouseUp {
                if isInside {
                    if isCompleting {
                        completionHandler?()
                    } else {
                        showActionFeedback()
                        DispatchQueue.main.async { [weak self] in
                            self?.sendConfiguredAction()
                        }
                    }
                }
                isCompletionPressed = false
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

    func showActionFeedback() {
        isActivating = true
        displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isActivating = false
        }
    }

    private func sendConfiguredAction() {
        guard let action else {
            return
        }

        NSApp.sendAction(action, to: target, from: self)
    }

    static func height(for title: String, index: Int, scale: CGFloat) -> CGFloat {
        let font = FocusFonts.todo(index: index, scale: scale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle(index: index, font: font, scale: scale)
        ]
        let rect = NSString(string: "\(index + 1). \(title)").boundingRect(
            with: NSSize(
                width: textWidth(scale: scale),
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        return max(42 * scale, ceil(rect.height) + (6 * scale))
    }

    private static func attributedTitle(index: Int, title: String, scale: CGFloat) -> NSAttributedString {
        let font = FocusFonts.todo(index: index, scale: scale)
        let fullTitle = "\(index + 1). \(title)"
        let attributed = NSMutableAttributedString(
            string: fullTitle,
            attributes: [
                .font: font,
                .foregroundColor: FocusColors.text,
                .paragraphStyle: paragraphStyle(index: index, font: font, scale: scale)
            ]
        )

        let actionableRange: NSRange?
        switch WeeklyFocusTodoActionResolver.resolve(title) {
        case .copySessionID(let sessionID):
            actionableRange = NSString(string: fullTitle).range(of: sessionID)
        case .openURL(let url):
            actionableRange = NSString(string: fullTitle).range(of: url.absoluteString)
        case .openBrainWikilink(let target):
            actionableRange = BrainWikilinkResolver.wikilinks(in: fullTitle)
                .first(where: { $0.target == target })?
                .range
        case .launchCopilot:
            actionableRange = nil
        }

        if let actionableRange, actionableRange.location != NSNotFound {
            attributed.addAttribute(
                .foregroundColor,
                value: FocusColors.link,
                range: actionableRange
            )
        }

        return attributed
    }

    private static func paragraphStyle(index: Int, font: NSFont, scale: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2 * scale
        style.headIndent = prefixWidth(index: index, font: font)
        return style
    }

    private static func prefixWidth(index: Int, font: NSFont) -> CGFloat {
        NSString(string: "\(index + 1). ").size(withAttributes: [.font: font]).width
    }

    private static func textWidth(scale: CGFloat) -> CGFloat {
        FocusLayout.rowWidth(scale: scale) - (34 * scale)
    }

    private var completionRect: NSRect {
        let size = max(16, 18 * layoutScale)
        return NSRect(
            x: bounds.maxX - size - (4 * layoutScale),
            y: floor((bounds.height - size) / 2),
            width: size,
            height: size
        )
    }

    private func drawCompletionCheckbox() {
        let rect = completionRect.insetBy(dx: 1, dy: 1)
        let color = isCompletionPressed
            ? FocusColors.accent
            : FocusColors.text.withAlphaComponent(0.45)
        color.setStroke()
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: 4 * layoutScale,
            yRadius: 4 * layoutScale
        )
        path.lineWidth = max(1, 1.5 * layoutScale)
        path.stroke()
    }
}

enum FocusLayout {
    static let numberWidth: CGFloat = 44
    static let columnGap: CGFloat = 12
    static let bodyWidth: CGFloat = 940
    static let baseRowWidth: CGFloat = numberWidth + columnGap + bodyWidth
    static let baseSpacing: CGFloat = 16
    static let overflowTodoLimit = 5

    static func rowWidth(scale: CGFloat) -> CGFloat {
        baseRowWidth * scale
    }

    static func spacing(scale: CGFloat) -> CGFloat {
        baseSpacing * scale
    }
}

enum FocusFonts {
    static func todo(index: Int, scale: CGFloat) -> NSFont {
        named(
            "Avenir Next",
            size: (index == 0 ? 30 : 28) * scale,
            weight: index == 0 ? .semibold : .medium
        )
    }

    static func overflow(index: Int, scale: CGFloat) -> NSFont {
        named(
            "Avenir Next",
            size: CGFloat(Swift.max(13, 18 - index)) * scale,
            weight: .regular
        )
    }

    static func input(scale: CGFloat) -> NSFont {
        named("Avenir Next", size: 24 * scale, weight: .regular)
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
    private var contentScale: CGFloat = 1
    private var displayedOverflowLimit = 1

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

        if menuItem.action == #selector(openWeeklyNoteMenuItem(_:)) {
            return snapshot != nil
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

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let focusMenuItem = NSMenuItem()
        let focusMenu = NSMenu(title: "Focus")
        for index in 0..<5 {
            let item = NSMenuItem(
                title: "Activate Item \(index + 1)",
                action: #selector(openTodoMenuItem(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.keyEquivalentModifierMask = [.command]
            item.tag = index
            item.target = self
            focusMenu.addItem(item)
        }
        focusMenu.addItem(.separator())
        let weeklyNoteItem = NSMenuItem(
            title: "Open Weekly Note",
            action: #selector(openWeeklyNoteMenuItem(_:)),
            keyEquivalent: "o"
        )
        weeklyNoteItem.keyEquivalentModifierMask = [.command]
        weeklyNoteItem.target = self
        focusMenu.addItem(weeklyNoteItem)
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

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = FocusLayout.spacing(scale: contentScale)
        root.setScalableContentView(contentStack)

        return root
    }

    private func reload() {
        do {
            let snapshot = try WeeklyFocusReader().read(
                todoLimit: 5,
                overflowLimit: FocusLayout.overflowTodoLimit
            )
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
        let layout = fittedLayout(for: snapshot)
        contentScale = layout.scale
        displayedOverflowLimit = layout.overflowLimit
        contentStack.spacing = FocusLayout.spacing(scale: contentScale)
        clearContent()

        if snapshot.todos.isEmpty {
            contentStack.addArrangedSubview(messageLabel("No TODOs"))
        } else {
            for (index, todo) in snapshot.todos.enumerated() {
                contentStack.addArrangedSubview(todoRow(index: index, title: todo))
            }
        }

        if !snapshot.overflowTodos.isEmpty {
            addOverflowTodos(snapshot.overflowTodos)
        }

        contentStack.addArrangedSubview(captureRow())
        contentStack.superview?.needsLayout = true
        contentStack.superview?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.captureField)
        }
    }

    private func renderError(_ error: Error) {
        clearContent()
        contentStack.addArrangedSubview(messageLabel(error.localizedDescription))
        contentStack.superview?.needsLayout = true
        contentStack.superview?.layoutSubtreeIfNeeded()
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

    private func addOverflowTodos(_ todos: [String]) {
        let shown = Array(todos.prefix(displayedOverflowLimit))
        for (index, todo) in shown.enumerated() {
            let label = overflowLabel(todo, index: index)
            contentStack.addArrangedSubview(label)
        }
    }

    private func captureRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0

        captureField.placeholderString = ""
        captureField.font = FocusFonts.input(scale: contentScale)
        captureField.textColor = primaryTextColor
        captureField.backgroundColor = FocusColors.fieldBackground
        captureField.layer?.borderColor = FocusColors.fieldBorder.cgColor
        captureField.focusRingType = .default
        captureField.target = self
        captureField.action = #selector(todoSubmitted(_:))
        captureField.delegate = self
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.widthAnchor.constraint(
            equalToConstant: FocusLayout.rowWidth(scale: contentScale)
        ).isActive = true

        row.addArrangedSubview(captureField)
        return row
    }

    private func todoButton(index: Int, title: String) -> TodoRowButton {
        let button = TodoRowButton(index: index, title: title, scale: contentScale)
        button.target = self
        button.action = #selector(todoButtonPressed(_:))
        button.completionHandler = { [weak self] in
            self?.markDone(at: index)
        }
        todoButtons.append(button)
        return button
    }

    private func messageLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = FocusFonts.todo(index: 0, scale: contentScale)
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
        label.font = FocusFonts.overflow(index: index, scale: contentScale)
        let alpha = Swift.max(0.10, 0.38 - (Double(index) * 0.035))
        label.textColor = secondaryTextColor.withAlphaComponent(alpha)
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(
            equalToConstant: FocusLayout.rowWidth(scale: contentScale)
        ).isActive = true
        return label
    }

    private func fittedLayout(for snapshot: WeeklyFocusSnapshot) -> (scale: CGFloat, overflowLimit: Int) {
        let availableSize = (window?.contentView as? FocusRootView)?.availableContentSize
            ?? NSSize(width: 1100, height: 700)
        let overflowLimit: Int
        if availableSize.height < 650 {
            overflowLimit = 1
        } else if availableSize.height < 850 {
            overflowLimit = 2
        } else {
            overflowLimit = 3
        }

        var lowerBound: CGFloat = 0.05
        var upperBound = max(
            lowerBound,
            min(1, availableSize.width / FocusLayout.baseRowWidth)
        )
        for _ in 0..<18 {
            let candidate = (lowerBound + upperBound) / 2
            if estimatedContentHeight(
                snapshot: snapshot,
                scale: candidate,
                overflowLimit: overflowLimit
            ) <= availableSize.height {
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }

        return (lowerBound * 0.98, overflowLimit)
    }

    private func estimatedContentHeight(
        snapshot: WeeklyFocusSnapshot,
        scale: CGFloat,
        overflowLimit: Int
    ) -> CGFloat {
        var heights = snapshot.todos.enumerated().map { index, todo in
            TodoRowButton.height(for: todo, index: index, scale: scale)
        }

        let shownOverflowCount = min(snapshot.overflowTodos.count, overflowLimit)
        for index in 0..<shownOverflowCount {
            heights.append(ceil(FocusFonts.overflow(index: index, scale: scale).boundingRectForFont.height))
        }

        heights.append(ceil(FocusFonts.input(scale: scale).boundingRectForFont.height) + (10 * scale))
        return heights.reduce(0, +)
            + (CGFloat(Swift.max(0, heights.count - 1)) * FocusLayout.spacing(scale: scale))
    }

    @objc private func todoButtonPressed(_ sender: TodoRowButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            markDone(at: sender.todoIndex)
        } else {
            activateTodo(at: sender.todoIndex)
        }
    }

    @objc private func todoSubmitted(_ sender: Any) {
        submitTodo()
    }

    @objc private func openTodoMenuItem(_ sender: NSMenuItem) {
        activateTodo(at: sender.tag)
    }

    @objc private func openWeeklyNoteMenuItem(_ sender: Any) {
        openWeeklyNote()
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

    private func activateTodo(at index: Int) {
        guard let snapshot, snapshot.todos.indices.contains(index) else {
            return
        }

        showActionFeedback(at: index)
        let todo = snapshot.todos[index]
        switch WeeklyFocusTodoActionResolver.resolve(todo) {
        case .copySessionID(let sessionID):
            copySessionID(sessionID)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .openBrainWikilink(let target):
            openBrainWikilink(target)
        case .launchCopilot:
            launchTodo(at: index)
        }
    }

    private func launchTodo(at index: Int) {
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

    private func showActionFeedback(at index: Int) {
        guard todoButtons.indices.contains(index) else {
            return
        }

        todoButtons[index].showActionFeedback()
    }

    private func openWeeklyNote() {
        guard let snapshot else {
            showAlert(title: "Could not open weekly note", message: "Weekly note is not loaded.")
            return
        }

        do {
            try openWeeklyNoteInVSCodeInsiders(path: snapshot.weeklyNotePath)
        } catch {
            showAlert(title: "Could not open weekly note", message: error.localizedDescription)
        }
    }

    private func openWeeklyNoteInVSCodeInsiders(path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let openPath = "/usr/bin/open"

        do {
            try runOpenCommand(
                executable: openPath,
                arguments: ["-b", "com.microsoft.VSCodeInsiders", fileURL.path]
            )
        } catch {
            try runOpenCommand(
                executable: openPath,
                arguments: ["-a", "Visual Studio Code - Insiders", fileURL.path]
            )
        }
    }

    private func copySessionID(_ sessionID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(sessionID, forType: .string) else {
            showAlert(title: "Could not copy session ID", message: "The system pasteboard rejected the session ID.")
            return
        }
    }

    private func openBrainWikilink(_ wikilinkTarget: String) {
        guard let snapshot else {
            showAlert(title: "Could not open Brain link", message: "Weekly note is not loaded.")
            return
        }

        guard let path = BrainWikilinkResolver.resolvePath(
            target: wikilinkTarget,
            brainRoot: snapshot.brainRoot
        ) else {
            showAlert(title: "Could not open Brain link", message: "No Brain file matched [[\(wikilinkTarget)]].")
            return
        }

        do {
            try openWeeklyNoteInVSCodeInsiders(path: path)
        } catch {
            showAlert(title: "Could not open Brain link", message: error.localizedDescription)
        }
    }

    private func runOpenCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw WeeklyFocusError.launchFailed(errorMessage?.isEmpty == false ? errorMessage! : "open exited with \(process.terminationStatus)")
        }
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
            activateTodo(at: number - 1)
            return nil
        }

        return event
    }

    func handleCommandKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        if handleTextEditingKeyEquivalent(characters) {
            return true
        }

        if let number = Int(characters), (1...5).contains(number) {
            activateTodo(at: number - 1)
            return true
        }

        if characters == "q" {
            NSApp.terminate(nil)
            return true
        }

        if characters == "o" {
            openWeeklyNote()
            return true
        }

        return false
    }

    private func handleTextEditingKeyEquivalent(_ characters: String) -> Bool {
        guard let editor = captureField.currentEditor() else {
            return false
        }

        switch characters {
        case "a":
            editor.selectAll(nil)
        case "c":
            editor.copy(nil)
        case "v":
            editor.paste(nil)
        case "x":
            editor.cut(nil)
        default:
            return false
        }

        return true
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
            window.contentView?.layoutSubtreeIfNeeded()
            if let snapshot {
                render(snapshot: snapshot)
            }
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
