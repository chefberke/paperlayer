import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var overlay: Overlay!
    private let breaks = BreakReminder()
    private let away = AwayScreen()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var awayKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = Overlay()
        if Settings.enabled { breaks.start() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Paperlayer")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        hotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey) { [weak self] in self?.toggle() }
        awayKey = HotKey(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [weak self] in self?.goAway() }
        refreshIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let main = NSMenuItem(title: "Eye breaks", action: #selector(toggle), keyEquivalent: "p")
        main.keyEquivalentModifierMask = [.control, .option]
        main.target = self
        main.state = Settings.enabled ? .on : .off
        menu.addItem(main)

        if Settings.enabled {
            let next = NSMenuItem(title: "Next break in \(breaks.minutesUntilBreak) min", action: nil, keyEquivalent: "")
            next.isEnabled = false
            menu.addItem(next)
            let now = NSMenuItem(title: "Take a break now", action: #selector(breakNow), keyEquivalent: "")
            now.target = self
            menu.addItem(now)
        }
        menu.addItem(timersItem())

        menu.addItem(.separator())
        let paper = NSMenuItem(title: "Paper mode", action: #selector(togglePaper), keyEquivalent: "")
        paper.target = self
        paper.state = Settings.paper ? .on : .off
        menu.addItem(paper)
        let awayItem = NSMenuItem(title: "Away mode", action: #selector(goAway), keyEquivalent: "b")
        awayItem.keyEquivalentModifierMask = [.control, .option]
        awayItem.target = self
        menu.addItem(awayItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Submenu with a few fixed choices per timing, the current one checked.
    private func timersItem() -> NSMenuItem {
        let sub = NSMenu()
        for setting in TimerSetting.allCases {
            if setting == .standEvery { sub.addItem(.separator()) }
            let header = NSMenuItem(title: setting.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            for seconds in setting.options {
                let option = NSMenuItem(title: TimerSetting.label(seconds), action: #selector(pickTimer(_:)), keyEquivalent: "")
                option.target = self
                option.indentationLevel = 1
                option.representedObject = [setting.rawValue: seconds]
                option.state = setting.value == seconds ? .on : .off
                sub.addItem(option)
            }
        }
        let item = NSMenuItem(title: "Timers", action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    @objc private func pickTimer(_ sender: NSMenuItem) {
        guard let pick = sender.representedObject as? [String: Int], let (key, seconds) = pick.first,
              let setting = TimerSetting(rawValue: key) else { return }
        setting.value = seconds
    }

    private func refreshIcon() {
        statusItem.button?.appearsDisabled = !Settings.enabled
    }

    @objc private func toggle() {
        Settings.enabled.toggle()
        if Settings.enabled { breaks.start() } else { breaks.stop() }
        refreshIcon()
    }

    @objc private func togglePaper() {
        Settings.paper.toggle()
        overlay.apply()
    }

    @objc private func goAway() {
        away.start()
    }

    @objc private func breakNow() {
        breaks.beginBreak()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
