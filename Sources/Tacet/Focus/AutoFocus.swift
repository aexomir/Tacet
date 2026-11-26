import AppKit

/// Decides when you've settled into one app (blur on) or are hopping between apps (blur off).
struct FocusDecider {
    let settleAfter: TimeInterval = 20      // seconds in one app before blurring
    let recentInput: TimeInterval = 5       // must have typed or scrolled this recently
    let hopWindow: TimeInterval = 10        // look back this far for app switches
    let hopsToLift = 3                      // this many switches in the window lifts the blur

    private var inAppSince: TimeInterval = 0
    private var switches: [TimeInterval] = []

    init(now: TimeInterval) { inAppSince = now }

    mutating func appChanged(at now: TimeInterval) {
        inAppSince = now
        switches.append(now)
    }

    /// true = blur, false = lift, nil = no opinion.
    mutating func decide(now: TimeInterval, idle: TimeInterval) -> Bool? {
        switches.removeAll { now - $0 > hopWindow }
        if switches.count >= hopsToLift { return false }
        if now - inAppSince >= settleAfter && idle <= recentInput { return true }
        return nil
    }
}

/// Runs the decider once a second. Only reports when its wish changes, so a manual
/// toggle in the panel sticks until you settle in or start hopping again.
@MainActor
final class AutoFocus {
    var onChange: (Bool) -> Void = { _ in }

    private var decider = FocusDecider(now: 0)
    private var lastWish: Bool?
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        decider = FocusDecider(now: ProcessInfo.processInfo.systemUptime)
        lastWish = nil
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != getpid() else { return }  // opening our own panel isn't a switch
            MainActor.assumeIsolated { self?.decider.appChanged(at: ProcessInfo.processInfo.systemUptime) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observer.map(NSWorkspace.shared.notificationCenter.removeObserver)
        observer = nil
    }

    private func tick() {
        // Time since the last key press or scroll; needs no permission and never sees what was typed.
        let idle = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        )
        guard let wish = decider.decide(now: ProcessInfo.processInfo.systemUptime, idle: idle),
              wish != lastWish else { return }
        lastWish = wish
        onChange(wish)
    }
}
