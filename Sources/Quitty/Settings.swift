import Foundation

/// User preferences, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    /// Apps that must never be quit, regardless of the user's exclusion list.
    static let alwaysExcluded: Set<String> = [
        "com.apple.finder",
    ]

    private let defaults = UserDefaults.standard
    private let enabledKey = "enabled"
    private let excludedKey = "excludedBundleIDs"

    private init() {
        defaults.register(defaults: [enabledKey: true, excludedKey: [String]()])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: excludedKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: excludedKey) }
    }

    func isExcluded(_ bundleID: String) -> Bool {
        Settings.alwaysExcluded.contains(bundleID) || excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        var ids = excludedBundleIDs
        if excluded {
            ids.insert(bundleID)
        } else {
            ids.remove(bundleID)
        }
        excludedBundleIDs = ids
    }
}
