import Foundation
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
    }
}
