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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var snapshot: WeeklyFocusSnapshot?
    private var keyMonitor: Any?
    private let titleLabel = NSTextField(labelWithString: "Weekly Focus")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()
    private let captureField = NSTextField()

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
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "Weekly Focus"
        window.collectionBehavior = [.canJoinAllSpaces]
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentView = buildRootView()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func buildRootView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.04, alpha: 1).cgColor

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 28
        container.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 56, weight: .bold)
        titleLabel.textColor = .white
        subtitleLabel.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(subtitleLabel)
        container.addArrangedSubview(contentStack)
        root.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 80),
            container.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -80),
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
        subtitleLabel.stringValue = "Up to five current TODOs from \(snapshot.weeklyNotePath)"
        clearContent()

        if snapshot.todos.isEmpty {
            contentStack.addArrangedSubview(messageLabel("No unchecked TODOs in this week's note."))
        } else {
            for (index, todo) in snapshot.todos.enumerated() {
                contentStack.addArrangedSubview(todoRow(index: index, title: todo))
            }
        }

        if !snapshot.overflowTodos.isEmpty {
            contentStack.addArrangedSubview(overflowSection(snapshot.overflowTodos))
        }

        contentStack.addArrangedSubview(captureRow())

        let capturedLabel = snapshot.capturedCount == 1 ? "item" : "items"
        contentStack.addArrangedSubview(secondaryLabel("Captured: \(snapshot.capturedCount) unchecked \(capturedLabel)"))

        if !snapshot.waiting.isEmpty {
            contentStack.addArrangedSubview(secondaryLabel("Waiting: \(snapshot.waiting.joined(separator: " | "))"))
        }

        contentStack.addArrangedSubview(secondaryLabel("Click an item or press 1-5 to work it. Click Done or press ⌘1-⌘5 to mark done. C captures, R refreshes, Esc/Q quits."))
    }

    private func renderError(_ error: Error) {
        subtitleLabel.stringValue = "Could not read the current weekly note"
        clearContent()
        contentStack.addArrangedSubview(messageLabel(error.localizedDescription))
        contentStack.addArrangedSubview(secondaryLabel("Press R to retry, Esc or Q to quit."))
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
        row.alignment = .centerY
        row.spacing = 16
        row.addArrangedSubview(todoButton(index: index, title: title))
        row.addArrangedSubview(doneButton(index: index))
        return row
    }

    private func overflowSection(_ todos: [String]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let shown = Array(todos.prefix(8))
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
        row.spacing = 12

        captureField.placeholderString = "Quick capture to ## Captured"
        captureField.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        captureField.target = self
        captureField.action = #selector(captureSubmitted(_:))
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.widthAnchor.constraint(greaterThanOrEqualToConstant: 720).isActive = true

        let button = NSButton(title: "Capture", target: self, action: #selector(captureSubmitted(_:)))
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        row.addArrangedSubview(captureField)
        row.addArrangedSubview(button)
        return row
    }

    private func todoButton(index: Int, title: String) -> NSButton {
        let button = NSButton(title: "\(index + 1). \(title)", target: self, action: #selector(todoButtonPressed(_:)))
        button.tag = index
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 30, weight: index == 0 ? .bold : .medium)
        button.alignment = .left
        button.contentTintColor = .white
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 820).isActive = true
        return button
    }

    private func doneButton(index: Int) -> NSButton {
        let button = NSButton(title: "Done", target: self, action: #selector(doneButtonPressed(_:)))
        button.tag = index
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        button.contentTintColor = NSColor(calibratedRed: 0.7, green: 1.0, blue: 0.7, alpha: 1)
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private func messageLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 30, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 0
        return label
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        label.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        label.maximumNumberOfLines = 0
        return label
    }

    private func overflowLabel(_ text: String, index: Int) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: CGFloat(Swift.max(14, 22 - index)), weight: .regular)
        let alpha = Swift.max(0.16, 0.42 - (Double(index) * 0.04))
        label.textColor = NSColor(calibratedWhite: 0.72, alpha: alpha)
        label.maximumNumberOfLines = 1
        return label
    }

    @objc private func todoButtonPressed(_ sender: NSButton) {
        launchTodo(at: sender.tag)
    }

    @objc private func doneButtonPressed(_ sender: NSButton) {
        markDone(at: sender.tag)
    }

    @objc private func captureSubmitted(_ sender: Any) {
        let text = captureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        guard let snapshot else {
            return
        }

        do {
            try WeeklyFocusReader.appendCapture(
                text,
                weeklyNotePath: snapshot.weeklyNotePath
            )
            captureField.stringValue = ""
            window?.makeFirstResponder(nil)
            reload()
        } catch {
            showAlert(title: "Could not capture", message: error.localizedDescription)
        }
    }

    private func launchTodo(at index: Int) {
        guard let snapshot, snapshot.todos.indices.contains(index) else {
            return
        }

        do {
            try CmuxFocusLauncher.launch(
                todo: snapshot.todos[index],
                brainRoot: snapshot.brainRoot
            )
        } catch {
            showAlert(title: "Could not open cmux", message: error.localizedDescription)
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
        if let firstResponder = window?.firstResponder,
           let editor = captureField.currentEditor(),
           firstResponder === editor {
            return event
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
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
            if event.modifierFlags.contains(.command) {
                markDone(at: number - 1)
            } else {
                launchTodo(at: number - 1)
            }
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
