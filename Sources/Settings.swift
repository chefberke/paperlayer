import Foundation

/// User preferences: automatic eye breaks and the paper overlay, each on or off.
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
