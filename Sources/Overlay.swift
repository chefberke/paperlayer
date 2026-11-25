import AppKit

/// Click-through window that covers one screen, above everything including the menu bar.
final class OverlayWindow: NSWindow {
    /// How much of the paper texture covers the screen. Tuned to match Paperman's look.
    private static let coverage: Float = 0.06

    init(screen: NSScreen, texture: NSImage) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep the effect out of screenshots and screen sharing.
        sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        // Layer opacity does the blending; a pattern color's own alpha is ignored.
        let paper = CALayer()
        paper.frame = view.bounds
        paper.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        paper.backgroundColor = NSColor(patternImage: texture).cgColor
        paper.opacity = Self.coverage
        view.layer?.addSublayer(paper)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class Overlay {
    private var windows: [OverlayWindow] = []
    private var textures: [CGFloat: NSImage] = [:]

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        rebuild()
    }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0, texture: texture(scale: $0.backingScaleFactor)) }
        apply()
    }

    func apply() {
        for w in windows {
            if Settings.paper { w.orderFrontRegardless() } else { w.orderOut(nil) }
        }
    }

    private func texture(scale: CGFloat) -> NSImage {
        if let t = textures[scale] { return t }
        let t = PaperTexture.make(scale: scale)
        textures[scale] = t
        return t
    }
}
