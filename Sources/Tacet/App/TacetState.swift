import AppKit
import Observation

/// Everything the panel shows, kept in sync with the blur engine and saved between launches.
@MainActor @Observable
final class TacetState {
    @ObservationIgnored private let engine = BlurEngine()
    @ObservationIgnored private let autoFocus = AutoFocus()
    @ObservationIgnored private let defaults = UserDefaults.standard

    var isOn = false {
        didSet { isOn ? engine.start() : engine.stop() }
    }
    var depth: Double {
        didSet { engine.depth = depth; defaults.set(depth, forKey: "depth") }
    }
    var clearApps: [String] {
        didSet { engine.clearApps = Set(clearApps); defaults.set(clearApps, forKey: "alwaysClear") }
    }
    var autoFocusOn: Bool {
        didSet {
            defaults.set(autoFocusOn, forKey: "autoFocus")
            autoFocusOn ? autoFocus.start() : autoFocus.stop()
        }
    }

    init() {
        depth = defaults.object(forKey: "depth") as? Double ?? 0.8
        clearApps = defaults.stringArray(forKey: "alwaysClear") ?? []
        autoFocusOn = defaults.object(forKey: "autoFocus") as? Bool ?? true
        engine.depth = depth
        engine.clearApps = Set(clearApps)
        autoFocus.onChange = { [weak self] on in self?.isOn = on }
        if autoFocusOn { autoFocus.start() }
        pauseWhileScreenIsUnseen()
    }

    /// Stops both timers while the display sleeps, the screen is locked, or another user is active.
    /// TacetState lives as long as the app, so the observers are never removed.
    private func pauseWhileScreenIsUnseen() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name, Bool)] = [
            (workspace, NSWorkspace.screensDidSleepNotification, true),
            (workspace, NSWorkspace.screensDidWakeNotification, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), false),
        ]
        for (center, name, paused) in events {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.engine.setPaused(paused)
                    self?.autoFocus.setPaused(paused)
                }
            }
        }
    }
}
