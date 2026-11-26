import AppKit

/// The two kinds of break this app asks for.
enum BreakKind {
    /// 20-20-20: look far away for 20 seconds. The intervention in this app with
    /// evidence behind it (Talens-Estarelles et al., 2022).
    case eyes
    /// An hour at the screen without stepping away: stand up and move for 5 minutes.
    case stand

    var seconds: Int {
        switch self {
        case .eyes: return TimerSetting.eyeLength.value
        case .stand: return TimerSetting.standLength.value
        }
    }

    var title: String {
        switch self {
        case .eyes: return "Look away"
        case .stand: return "Stand up"
        }
    }

    var message: String {
        switch self {
        case .eyes: return "Look at something 20 feet (6 m) away and blink slowly a few times."
        case .stand:
            let seated = TimerSetting.standEvery.value / 60
            let sitting = seated == 60 ? "an hour" : "\(seated) minutes"
            return "You have been at the screen for \(sitting). Stand up, stretch and walk for \(seconds / 60) minutes."
        }
    }
}

/// Break reminders: after 20 minutes of active use, dim every screen for 20 seconds and
/// ask the user to look far away. After an hour at the screen with no real pause, ask
/// them to stand up for 5 minutes. All four timings can be changed from the menu.
final class BreakReminder {
    private static var workLimit: TimeInterval { TimeInterval(TimerSetting.eyeEvery.value) }
    private static let tick: TimeInterval = 15
    /// Idle this long already counts as a break, so the count restarts.
    private static let naturalBreak: TimeInterval = 5 * 60
    /// Idle this long means the user stepped away; that time is not counted as work.
    private static let away: TimeInterval = 60
    /// At the screen this long without a pause of `standPause` asks for a stand-up break.
    private static var standLimit: TimeInterval { TimeInterval(TimerSetting.standEvery.value) }
    /// Idle this long counts as having left the desk, so the hour starts over.
    private static let standPause: TimeInterval = 2 * 60

    private var timer: Timer?
    private var countdown: Timer?
    private var worked: TimeInterval = 0
    private var seated: TimeInterval = 0
    private var windows: [BreakWindow] = []

    var minutesUntilBreak: Int { max(1, Int(ceil((Self.workLimit - worked) / 60))) }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.worked = 0
            self?.seated = 0
        }
    }

    func start() {
        worked = 0
        seated = 0
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
        if idle >= Self.standPause { seated = 0 } else { seated += Self.tick }
        if idle >= Self.naturalBreak {
            worked = 0
            return
        }
        if idle < Self.away { worked += Self.tick }
        if seated >= Self.standLimit {
            beginBreak(.stand)
        } else if worked >= Self.workLimit {
            beginBreak(.eyes)
        }
    }

    func beginBreak(_ kind: BreakKind = .eyes) {
        guard windows.isEmpty else { return }
        worked = 0
        if kind == .stand { seated = 0 }
        var remaining = kind.seconds
        windows = NSScreen.screens.map { BreakWindow(screen: $0, kind: kind) { [weak self] in self?.endBreak() } }
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

/// Dimmed full-screen panel. Non-activating, so it never steals focus and typing keeps
/// going to the app below. Only the Close button ends it early: a stray click while
/// working must not dismiss the break by accident.
final class BreakWindow: NSPanel {
    private let count = NSTextField(labelWithString: "")
    private let onClose: () -> Void

    init(screen: NSScreen, kind: BreakKind, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = NSColor(white: 0.04, alpha: 0.62)
        hasShadow = false
        isReleasedWhenClosed = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let title = label(kind.title, size: 44, weight: .semibold, alpha: 0.95)
        let body = label(kind.message, size: 17, weight: .regular, alpha: 0.75)
        count.font = .monospacedDigitSystemFont(ofSize: 64, weight: .light)
        count.textColor = NSColor(white: 1, alpha: 0.9)
        let close = CloseButton(label: "Close")
        close.target = self
        close.action = #selector(closeTapped)

        let stack = NSStackView(views: [title, body, count, close])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(30, after: body)
        stack.setCustomSpacing(28, after: count)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

    func update(_ seconds: Int) {
        count.stringValue = seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)"
    }

    func dismiss() {
        // Strong capture keeps the panel alive until the fade finishes.
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.8; animator().alphaValue = 0 }) { self.orderOut(nil) }
    }

    @objc private func closeTapped() { onClose() }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor(white: 1, alpha: alpha)
        return l
    }
}

/// Quiet outlined button: thin light border, dim label, a little brighter on hover.
private final class CloseButton: NSButton {
    private let label: String
    private var hovering = false { didSet { restyle() } }

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            heightAnchor.constraint(equalToConstant: 30),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    // The panel never becomes key, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func restyle() {
        let alpha: CGFloat = hovering ? 0.85 : 0.5
        layer?.borderColor = NSColor(white: 1, alpha: hovering ? 0.45 : 0.22).cgColor
        layer?.backgroundColor = NSColor(white: 1, alpha: hovering ? 0.08 : 0).cgColor
        attributedTitle = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: alpha),
        ])
    }
}
