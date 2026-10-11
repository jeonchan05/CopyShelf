import Foundation

@MainActor
final class AppPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // The old recordingEnabled flag also represented the old default-off behaviour.
    // Use an explicit pause preference so upgrading starts automatic recording once.
    var recordingEnabled: Bool {
        get { !defaults.bool(forKey: "recordingPaused") }
        set { defaults.set(!newValue, forKey: "recordingPaused") }
    }

    var hasSeenAutomaticRecording: Bool {
        get { defaults.bool(forKey: "hasSeenAutomaticRecording") }
        set { defaults.set(newValue, forKey: "hasSeenAutomaticRecording") }
    }

    var shortcut: KeyboardShortcut {
        get {
            guard let data = defaults.data(forKey: "historyShortcut"),
                  let value = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), value.isValid else { return .default }
            return value
        }
        set {
            guard newValue.isValid, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "historyShortcut")
        }
    }

    func shouldRecord(demo: Bool) -> Bool { !demo && recordingEnabled }
}
