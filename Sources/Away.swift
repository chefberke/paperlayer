import AppKit
import IOKit.pwr_mgt

/// Away screen for leaving the desk without sleeping the Mac: Matrix rain, a bouncing
/// EatBetter logo and a "Be right back" note. Any key or click brings the desktop back.
final class AwayScreen {
    private var windows: [AwayWindow] = []
    private var timer: Timer?
    private var frame = 0
    private var assertion: IOPMAssertionID = 0
    private var previousApp: NSRunningApplication?

    var isActive: Bool { !windows.isEmpty }

    func start() {
        guard windows.isEmpty else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        // The point of the mode is a screen that stays on, so hold off display sleep.
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Paperlayer away screen" as CFString, &assertion)

        let since = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        windows = NSScreen.screens.map { AwayWindow(screen: $0, since: since) { [weak self] in self?.stop() } }
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.present() }
        windows.first?.makeKey()
        NSCursor.setHiddenUntilMouseMoves(true)

        frame = 0
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard !windows.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        windows.forEach { $0.dismiss() }
        windows = []
        previousApp?.activate()
        previousApp = nil
    }

    private func step() {
        frame += 1
        // The logo moves every frame; the rain only every other one, which reads better.
        let rain = frame % 2 == 0
        for w in windows { w.away.step(rain: rain) }
    }
}

final class AwayWindow: NSWindow {
    let away: AwayView

    init(screen: NSScreen, since: String, onExit: @escaping () -> Void) {
        away = AwayView(frame: NSRect(origin: .zero, size: screen.frame.size), since: since, onExit: onExit)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        backgroundColor = .black
        isReleasedWhenClosed = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = away
    }

    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func present() {
        orderFrontRegardless()
        makeFirstResponder(away)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.6; animator().alphaValue = 1 }
    }

    func dismiss() {
        // Strong capture keeps the window alive until the fade finishes.
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; animator().alphaValue = 0 }) { self.orderOut(nil) }
    }
}

final class AwayView: NSView {
    private static let green = NSColor(red: 0.055, green: 0.855, blue: 0.549, alpha: 1)
    private static let pink = NSColor(red: 1, green: 0.067, blue: 0.518, alpha: 1)
    private static let logoColors: [NSColor] = [green, pink, .white]
    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789EATBETTER")
    private static let cellWidth: CGFloat = 14
    private static let cellHeight: CGFloat = 18

    private let onExit: () -> Void
    private let rainLayer = CALayer()
    private let logoBox = CALayer()
    private let logoFill = CALayer()
    private var rain: CGContext?
    private var drops: [Double] = []
    private var speeds: [Double] = []
    private var velocity = CGPoint(x: 2, y: 2)
    private var colorIndex = 0

    init(frame: NSRect, since: String, onExit: @escaping () -> Void) {
        self.onExit = onExit
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // The rain is drawn at one pixel per point and scaled up without smoothing,
        // which keeps it cheap on big screens and gives it a crisp retro look.
        let w = Int(frame.width), h = Int(frame.height)
        rain = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        rain?.setFillColor(NSColor.black.cgColor)
        rain?.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let columns = Int(frame.width / Self.cellWidth) + 1
        let rows = Double(frame.height / Self.cellHeight)
        drops = (0..<columns).map { _ in -Double.random(in: 0...rows) }
        speeds = (0..<columns).map { _ in Double.random(in: 0.45...1) }
        rainLayer.frame = bounds
        rainLayer.magnificationFilter = .nearest
        rainLayer.opacity = 0.55
        layer?.addSublayer(rainLayer)

        addLogo()
        addNote(since: since)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func keyDown(with event: NSEvent) { onExit() }
    override func mouseDown(with event: NSEvent) { onExit() }
    override func rightMouseDown(with event: NSEvent) { onExit() }

    private func addLogo() {
        guard let image = Bundle.main.image(forResource: "eatbetter-logo"),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let width: CGFloat = min(340, bounds.width * 0.3)
        let size = CGSize(width: width, height: width * CGFloat(cg.height) / CGFloat(cg.width))
        logoBox.frame = CGRect(origin: CGPoint(x: .random(in: 0...(bounds.width - size.width)),
                                               y: .random(in: 0...(bounds.height - size.height))), size: size)
        logoBox.shadowColor = NSColor.black.cgColor
        logoBox.shadowOpacity = 1
        logoBox.shadowRadius = 14
        logoBox.shadowOffset = .zero

        // The logo is black on transparent, so it is used as a mask over a solid fill
        // that changes color on every wall hit, like the old DVD screensaver.
        let mask = CALayer()
        mask.frame = CGRect(origin: .zero, size: size)
        mask.contents = cg
        mask.contentsGravity = .resizeAspect
        logoFill.frame = mask.frame
        logoFill.backgroundColor = Self.logoColors[colorIndex].cgColor
        logoFill.mask = mask
        logoBox.addSublayer(logoFill)
        layer?.addSublayer(logoBox)
        if Bool.random() { velocity.x = -velocity.x }
        if Bool.random() { velocity.y = -velocity.y }
    }

    private func addNote(since: String) {
        let title = label("Be right back", font: .monospacedSystemFont(ofSize: 30, weight: .semibold), alpha: 0.92)
        let detail = label("Away since \(since)", font: .monospacedSystemFont(ofSize: 14, weight: .regular), alpha: 0.55)
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -72),
        ])
    }

    private func label(_ text: String, font: NSFont, alpha: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = NSColor(white: 1, alpha: alpha)
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowBlurRadius = 10
        l.shadow = shadow
        return l
    }

    func step(rain advanceRain: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        moveLogo()
        if advanceRain, let image = drawRain() { rainLayer.contents = image }
        CATransaction.commit()
    }

    private func moveLogo() {
        var f = logoBox.frame
        f.origin.x += velocity.x
        f.origin.y += velocity.y
        var hit = false
        if f.minX <= 0 || f.maxX >= bounds.width {
            velocity.x = -velocity.x
            f.origin.x = max(0, min(f.origin.x, bounds.width - f.width))
            hit = true
        }
        if f.minY <= 0 || f.maxY >= bounds.height {
            velocity.y = -velocity.y
            f.origin.y = max(0, min(f.origin.y, bounds.height - f.height))
            hit = true
        }
        if hit {
            colorIndex = (colorIndex + 1) % Self.logoColors.count
            logoFill.backgroundColor = Self.logoColors[colorIndex].cgColor
        }
        logoBox.frame = f
    }

    private func drawRain() -> CGImage? {
        guard let ctx = rain else { return nil }
        let height = CGFloat(ctx.height)
        // A translucent black wash over the last frame turns old glyphs into fading trails.
        ctx.setFillColor(NSColor(white: 0, alpha: 0.09).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        let trail: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.green]
        let head: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(red: 0.8, green: 1, blue: 0.9, alpha: 1)]
        let rows = Double(height / Self.cellHeight)

        for i in drops.indices {
            let before = Int(drops[i])
            drops[i] += speeds[i]
            let row = Int(drops[i])
            guard row != before else { continue }
            let x = CGFloat(i) * Self.cellWidth
            // Repaint the previous head in green, then draw the new bright head below it.
            if before >= 0 { glyph(at: x, row: before, height: height, attributes: trail, in: ctx) }
            if row >= 0 { glyph(at: x, row: row, height: height, attributes: head, in: ctx) }
            if Double(row) > rows && Double.random(in: 0...1) > 0.97 {
                drops[i] = -Double.random(in: 0...(rows / 3))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func glyph(at x: CGFloat, row: Int, height: CGFloat, attributes: [NSAttributedString.Key: Any], in ctx: CGContext) {
        let y = height - CGFloat(row + 1) * Self.cellHeight
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: x, y: y, width: Self.cellWidth, height: Self.cellHeight))
        String(Self.glyphs.randomElement()!).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }
}
