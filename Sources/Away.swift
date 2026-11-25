import AppKit
import IOKit.pwr_mgt

/// Away screen for leaving the desk without sleeping the Mac: Matrix rain, a bouncing
/// EatBetter logo and a "Be right back" note. Any key or click brings the desktop back.
/// All motion runs as Core Animation on the GPU, so the CPU stays idle while it is up.
final class AwayScreen {
    private var windows: [AwayWindow] = []
    private var assertion: IOPMAssertionID = 0
    private var previousApp: NSRunningApplication?

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
    }

    func stop() {
        guard !windows.isEmpty else { return }
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        windows.forEach { $0.dismiss() }
        windows = []
        previousApp?.activate()
        previousApp = nil
    }
}

final class AwayWindow: NSWindow {
    private let away: AwayView

    init(screen: NSScreen, since: String, onExit: @escaping () -> Void) {
        away = AwayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                        scale: screen.backingScaleFactor, since: since, onExit: onExit)
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
        away.start()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.6; animator().alphaValue = 1 }
    }

    func dismiss() {
        // Strong capture keeps the window alive until the fade finishes.
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; animator().alphaValue = 0 }) {
            self.away.stop()
            self.orderOut(nil)
        }
    }
}

final class AwayView: NSView {
    private static let green = NSColor(red: 0.055, green: 0.855, blue: 0.549, alpha: 1)
    private static let pink = NSColor(red: 1, green: 0.067, blue: 0.518, alpha: 1)
    private static let logoColors: [NSColor] = [green, pink, .white]
    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789EATBETTER")
    private static let cellWidth: CGFloat = 14
    private static let cellHeight: CGFloat = 18
    /// Rain brightness. Baked into the glyphs, because opacity on the parent layer would
    /// make the window server composite the whole rain offscreen on every frame.
    private static let rainAlpha: CGFloat = 0.55
    /// Logo speed along each axis, in points per second.
    private static let logoSpeed: CGFloat = 110

    private let onExit: () -> Void
    private let scale: CGFloat
    private let rain = CALayer()
    private var strips: [CGImage] = []
    private let logoBox = CALayer()
    private let logoFill = CALayer()
    private var direction = CGPoint(x: 1, y: 1)
    private var colorIndex = 0
    private var running = false

    init(frame: NSRect, scale: CGFloat, since: String, onExit: @escaping () -> Void) {
        self.onExit = onExit
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        rain.frame = bounds
        layer?.addSublayer(rain)
        addLogo()
        addNote(since: since)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func keyDown(with event: NSEvent) { onExit() }
    override func mouseDown(with event: NSEvent) { onExit() }
    override func rightMouseDown(with event: NSEvent) { onExit() }

    func start() {
        running = true
        strips = (0..<24).map { _ in Self.makeStrip(length: .random(in: 8...28), scale: scale) }
        let columns = Int(bounds.width / Self.cellWidth) + 1
        for i in 0..<columns {
            let column = CALayer()
            column.anchorPoint = .zero
            column.contentsScale = scale
            column.position = CGPoint(x: CGFloat(i) * Self.cellWidth, y: bounds.height)
            rain.addSublayer(column)
            fall(column, first: true)
        }
        bounce()
    }

    func stop() {
        running = false
        rain.sublayers?.forEach { $0.removeAllAnimations() }
        logoBox.removeAllAnimations()
    }

    // MARK: Rain

    /// One pre-rendered trail of glyphs that fades in from the top to a bright head at the bottom.
    private static func makeStrip(length: Int, scale: CGFloat) -> CGImage {
        let w = Int(cellWidth * scale), h = Int(CGFloat(length) * cellHeight * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
        for k in 0..<length {
            let isHead = k == length - 1
            let fade = pow(CGFloat(k + 1) / CGFloat(length), 1.6) * rainAlpha
            let color = isHead ? NSColor(red: 0.8, green: 1, blue: 0.9, alpha: rainAlpha) : green.withAlphaComponent(fade)
            let y = CGFloat(length - 1 - k) * cellHeight
            String(glyphs.randomElement()!).draw(at: NSPoint(x: 0, y: y), withAttributes: [.font: font, .foregroundColor: color])
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// Drops one column from above the top edge to below the bottom, then starts it again
    /// with a fresh trail and speed. The first pass starts mid-screen so the rain is already full.
    private func fall(_ column: CALayer, first: Bool) {
        guard running else { return }
        let strip = strips.randomElement()!
        let stripHeight = CGFloat(strip.height) / scale
        let top = bounds.height, bottom = -stripHeight
        let from = first ? CGFloat.random(in: bottom...top) : top
        let speed = CGFloat.random(in: 140...420)
        let delay = first ? 0 : Double.random(in: 0...2.5)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        column.contents = strip
        column.bounds = CGRect(x: 0, y: 0, width: Self.cellWidth, height: stripHeight)
        // The model value sits below the screen, so the column stays hidden during the delay.
        column.position.y = bottom
        CATransaction.setCompletionBlock { [weak self, weak column] in
            guard let self, let column else { return }
            self.fall(column, first: false)
        }
        let anim = CABasicAnimation(keyPath: "position.y")
        anim.fromValue = from
        anim.toValue = bottom
        anim.duration = Double((from - bottom) / speed)
        anim.beginTime = CACurrentMediaTime() + delay
        column.add(anim, forKey: "fall")
        CATransaction.commit()
    }

    // MARK: Logo

    private func addLogo() {
        guard let image = Bundle.main.image(forResource: "eatbetter-logo"),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let width: CGFloat = min(340, bounds.width * 0.3)
        let size = CGSize(width: width, height: width * CGFloat(cg.height) / CGFloat(cg.width))
        logoBox.anchorPoint = .zero
        logoBox.bounds = CGRect(origin: .zero, size: size)
        logoBox.position = CGPoint(x: .random(in: 0...(bounds.width - size.width)),
                                   y: .random(in: 0...(bounds.height - size.height)))
        logoBox.shadowColor = NSColor.black.cgColor
        logoBox.shadowOpacity = 1
        logoBox.shadowRadius = 14
        logoBox.shadowOffset = .zero
        // Cache the logo and its blur as one bitmap so the GPU just slides it around.
        logoBox.shouldRasterize = true
        logoBox.rasterizationScale = scale

        // The logo is black on transparent, so it is used as a mask over a solid fill
        // that changes color on every wall hit, like the old DVD screensaver.
        let mask = CALayer()
        mask.frame = logoBox.bounds
        mask.contents = cg
        mask.contentsGravity = .resizeAspect
        logoFill.frame = logoBox.bounds
        logoFill.backgroundColor = Self.logoColors[colorIndex].cgColor
        logoFill.mask = mask
        logoBox.addSublayer(logoFill)
        layer?.addSublayer(logoBox)
        direction = CGPoint(x: Bool.random() ? 1 : -1, y: Bool.random() ? 1 : -1)
    }

    /// Glides the logo in a straight line to the next wall, then turns it and recolors it there.
    private func bounce() {
        guard running, logoBox.superlayer != nil else { return }
        let start = logoBox.position
        let maxX = bounds.width - logoBox.bounds.width, maxY = bounds.height - logoBox.bounds.height
        let tx = (direction.x > 0 ? maxX - start.x : start.x) / Self.logoSpeed
        let ty = (direction.y > 0 ? maxY - start.y : start.y) / Self.logoSpeed
        let t = max(0.001, min(tx, ty))
        let end = CGPoint(x: min(maxX, max(0, start.x + direction.x * Self.logoSpeed * t)),
                          y: min(maxY, max(0, start.y + direction.y * Self.logoSpeed * t)))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        logoBox.position = end
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.running else { return }
            if tx <= t + 0.0001 { self.direction.x = -self.direction.x }
            if ty <= t + 0.0001 { self.direction.y = -self.direction.y }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.colorIndex = (self.colorIndex + 1) % Self.logoColors.count
            self.logoFill.backgroundColor = Self.logoColors[self.colorIndex].cgColor
            CATransaction.commit()
            self.bounce()
        }
        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = start
        anim.toValue = end
        anim.duration = Double(t)
        logoBox.add(anim, forKey: "bounce")
        CATransaction.commit()
    }

    // MARK: Note

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
}
