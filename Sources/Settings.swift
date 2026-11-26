import Foundation

/// User preferences: automatic breaks and the paper overlay, each on or off.
enum Settings {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }

    static var paper: Bool {
        get { UserDefaults.standard.bool(forKey: "paper") }
        set { UserDefaults.standard.set(newValue, forKey: "paper") }
    }
}

/// Break timings the user can pick from the menu. Values are stored in seconds.
enum TimerSetting: String, CaseIterable {
    case eyeEvery, eyeLength, standEvery, standLength

    var title: String {
        switch self {
        case .eyeEvery: return "Eye break every"
        case .eyeLength: return "Eye break length"
        case .standEvery: return "Stand up after"
        case .standLength: return "Stand-up break length"
        }
    }

    var options: [Int] {
        switch self {
        case .eyeEvery: return [15, 20, 30, 45].map { $0 * 60 }
        case .eyeLength: return [20, 30, 60]
        case .standEvery: return [30, 45, 60, 90].map { $0 * 60 }
        case .standLength: return [2, 5, 10].map { $0 * 60 }
        }
    }

    var defaultValue: Int {
        switch self {
        case .eyeEvery: return 20 * 60
        case .eyeLength: return 20
        case .standEvery: return 60 * 60
        case .standLength: return 5 * 60
        }
    }

    var value: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: key)
            return stored > 0 ? stored : defaultValue
        }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    private var key: String { "timer.\(rawValue)" }

    /// "20 sec", "5 min".
    static func label(_ seconds: Int) -> String {
        seconds < 60 || seconds % 60 != 0 ? "\(seconds) sec" : "\(seconds / 60) min"
    }
}
