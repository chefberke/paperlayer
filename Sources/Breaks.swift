import AppKit

/// 20-20-20 reminder: after 20 minutes of active use, dim every screen for 20 seconds
/// and ask the user to look far away and blink. The only intervention in this app with
/// evidence behind it (Talens-Estarelles et al., 2022).
final class BreakReminder {
    private static let workLimit: TimeInterval = 20 * 60
    private static let breakLength = 20
    private static let tick: TimeInterval = 15
    /// Idle this long already counts as a break, so the count restarts.
    private static let naturalBreak: TimeInterval = 5 * 60
    /// Idle this long means the user stepped away; that time is not counted as work.
    private static let away: TimeInterval = 60

    private var timer: Timer?
    private var countdown: Timer?
    private var worked: TimeInterval = 0
    private var windows: [BreakWindow] = []

    var minutesUntilBreak: Int { max(1, Int(ceil((Self.workLimit - worked) / 60))) }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.worked = 0 }
    }

    func start() {
        worked = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in self?.check() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endBreak()
    }

    private func check() {
        guard windows.isEmpty else { return }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= Self.naturalBreak {
            worked = 0
            return
        }
        if idle < Self.away { worked += Self.tick }
        if worked >= Self.workLimit { beginBreak() }
    }

    func beginBreak() {
        guard windows.isEmpty else { return }
        worked = 0
        var remaining = Self.breakLength
        windows = NSScreen.screens.map { BreakWindow(screen: $0) { [weak self] in self?.endBreak() } }
        windows.forEach { $0.present(remaining) }
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            remaining -= 1
            if remaining <= 0 { self?.endBreak() } else { self?.windows.forEach { $0.update(remaining) } }
        }
    }

    func endBreak() {
        countdown?.invalidate()
        countdown = nil
        windows.forEach { $0.dismiss() }
        windows = []
    }
}

/// Dimmed full-screen panel. Non-activating, so it never steals focus; a click skips the break.
final class BreakWindow: NSPanel {
    private let count = NSTextField(labelWithString: "")

    init(screen: NSScreen, onSkip: @escaping () -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = NSColor(white: 0.04, alpha: 0.62)
        hasShadow = false
        isReleasedWhenClosed = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let title = label("Look away", size: 44, weight: .semibold, alpha: 0.95)
        let body = label("Look at something 20 feet (6 m) away and blink slowly a few times.", size: 17, weight: .regular, alpha: 0.75)
        count.font = .monospacedDigitSystemFont(ofSize: 64, weight: .light)
        count.textColor = NSColor(white: 1, alpha: 0.9)
        let hint = label("Click to skip", size: 12, weight: .regular, alpha: 0.45)

        let stack = NSStackView(views: [title, body, count, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(30, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = ClickView(frame: NSRect(origin: .zero, size: screen.frame.size), onClick: onSkip)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func present(_ seconds: Int) {
        update(seconds)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 1.2; animator().alphaValue = 1 }
    }

    func update(_ seconds: Int) { count.stringValue = "\(seconds)" }

    func dismiss() {
        // Strong capture keeps the panel alive until the fade finishes.
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.8; animator().alphaValue = 0 }) { self.orderOut(nil) }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor(white: 1, alpha: alpha)
        return l
    }
}

private final class ClickView: NSView {
    private let onClick: () -> Void

    init(frame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}
