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
                contentStack.addArrangedSubview(todoButton(index: index, title: todo))
            }
        }

        let capturedLabel = snapshot.capturedCount == 1 ? "item" : "items"
        contentStack.addArrangedSubview(secondaryLabel("Captured: \(snapshot.capturedCount) unchecked \(capturedLabel)"))

        if !snapshot.waiting.isEmpty {
            contentStack.addArrangedSubview(secondaryLabel("Waiting: \(snapshot.waiting.joined(separator: " | "))"))
        }

        contentStack.addArrangedSubview(secondaryLabel("Press 1-5 to work an item, R to refresh, Esc or Q to quit."))
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

    private func todoButton(index: Int, title: String) -> NSButton {
        let button = NSButton(title: "\(index + 1). \(title)", target: self, action: #selector(todoButtonPressed(_:)))
        button.tag = index
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 30, weight: index == 0 ? .bold : .medium)
        button.alignment = .left
        button.contentTintColor = .white
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 900).isActive = true
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

    @objc private func todoButtonPressed(_ sender: NSButton) {
        launchTodo(at: sender.tag)
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

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
