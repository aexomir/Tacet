import AppKit
import Observation

/// The timings and strengths you can adjust in Settings.
struct Tuning: Codable, Equatable {
    var settleAfter: TimeInterval = 20       // seconds in one app before Auto-focus blurs
    var recentInput: TimeInterval = 5        // ...as long as you typed or scrolled this recently
    var hopWindow: TimeInterval = 10         // look back this far for app switches
    var hopsToLift = 3                       // this many switches in that time lifts the blur
    var darkenAfterMinutes: Double = 5       // untouched this long: first darkening layer
    var darkenMoreAfterMinutes: Double = 30  // untouched this long: second darkening layer
    var darkness = 0.35                      // black opacity of each darkening layer
}

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
    var tuning: Tuning {
        didSet {
            apply(tuning)
            defaults.set(try? JSONEncoder().encode(tuning), forKey: "tuning")
        }
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
        tuning = defaults.data(forKey: "tuning").flatMap { try? JSONDecoder().decode(Tuning.self, from: $0) } ?? Tuning()
        apply(tuning)
        engine.depth = depth
        engine.clearApps = Set(clearApps)
        autoFocus.onChange = { [weak self] on in self?.isOn = on }
        if autoFocusOn { autoFocus.start() }
        pauseWhileScreenIsUnseen()
    }

    private func apply(_ tuning: Tuning) {
        autoFocus.tuning = tuning
        engine.deepenAfter = [tuning.darkenAfterMinutes * 60, tuning.darkenMoreAfterMinutes * 60]
        engine.darkness = tuning.darkness
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
