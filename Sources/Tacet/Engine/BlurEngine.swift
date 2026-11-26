import AppKit

/// The CGWindowList fields Tacet reads, parsed once per refresh.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let isNormal: Bool   // layer 0: an app's own window, not a menu, panel or the Dock
    let isVisible: Bool  // alpha > 0: web apps (PWAs) keep an invisible window in front of the real one
    let bounds: CGRect?  // global, top-left origin

    init?(_ w: [String: Any]) {
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let pid = w[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        self.id = id
        self.pid = pid
        isNormal = (w[kCGWindowLayer as String] as? Int) == 0
        isVisible = ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0
        bounds = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
    }
}

/// Covers every screen with click-through windows. The first layer, a blur, sits directly below the
/// focused window; extra dimming layers sit above windows you haven't touched in a while, so the
/// background fades further with neglect. macOS draws the blur (NSVisualEffectView, behind-window
/// blending), so no Screen Recording permission. Deeper layers dim instead of blurring again because
/// every stacked blur is another full-screen blur pass in WindowServer.
@MainActor
final class BlurEngine {
    var depth: Double = 0.8 {
        didSet { overlays.forEach { $0.window.alphaValue = alpha(for: $0.level) } }
    }

    /// Bundle IDs whose windows are cut out of the blur.
    var clearApps: Set<String> = [] {
        didSet { holes = nil; refresh() }
    }

    /// A window untouched this long gets one more dimming layer on top of it, per entry.
    static let deepenAfter: [TimeInterval] = [5 * 60, 30 * 60]

    private struct Overlay {
        let window: NSWindow
        let view: NSView  // NSVisualEffectView for layer 0, a plain dimming view for deeper layers
        let screenFrame: NSRect
        let level: Int  // 0 = below the focused window, 1... = deeper layers
    }

    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var anchors: [CGWindowID?] = []  // per level: the window each layer is placed against
    private var holes: [CGRect]?  // nil = masks need rebuilding
    private var frontPID: pid_t = 0  // cached: asking NSWorkspace each tick is a LaunchServices round trip
    private var activation: NSObjectProtocol?
    private var lastFocused: [CGWindowID: TimeInterval] = [:]
    private var startedAt: TimeInterval = 0

    private var isOn: Bool { !overlays.isEmpty }

    func start() {
        guard !isOn else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        overlays = (0...Self.deepenAfter.count).flatMap { level in
            NSScreen.screens.map { makeOverlay(for: $0, level: level) }
        }
        anchors = Array(repeating: nil, count: Self.deepenAfter.count + 1)
        holes = nil
        frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.frontPID = pid ?? 0
                self?.refresh()  // follow app switches right away instead of on the next tick
            }
        }
        // shortcut: polls the window list 4x a second because tracking window focus inside an app
        // without Accessibility has no notification; replace if it shows up in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.05  // lets macOS batch our wakeups with other timers
        refresh()
    }

    /// Stops polling while nobody can see the screen (display asleep, screen locked, user switched).
    func setPaused(_ paused: Bool) {
        timer?.fireDate = paused ? .distantFuture : Date()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activation.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activation = nil
        for window in overlays.map(\.window) {
            Self.fade(window, to: 0) { window.orderOut(nil) }
        }
        overlays = []
        anchors = []
        holes = nil
        lastFocused = [:]
    }

    private func refresh() {
        // While Tacet's own panel is in front, leave the blur where it is.
        guard isOn, frontPID != getpid() else { return }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap(WindowInfo.init)
        let now = ProcessInfo.processInfo.systemUptime
        let stack = Self.visibleWindows(in: windows, excluding: getpid())
        let front = Self.topWindow(in: windows, pid: frontPID)
        if let front { lastFocused[front] = now }
        lastFocused = lastFocused.filter { stack.contains($0.key) }

        let deep = front.map { front in
            Self.deepAnchors(stack: stack, front: front, thresholds: Self.deepenAfter) {
                now - (self.lastFocused[$0] ?? self.startedAt)
            }
        } ?? []
        let wanted = [front] + (deep.isEmpty ? Array(repeating: nil, count: Self.deepenAfter.count) : deep)
        // Re-place layer 0 if something slid between it and the focused window: on an app switch we can
        // run before macOS has raised the new window, and ordering against it then lands too low.
        let layerZero = Set(overlays.filter { $0.level == 0 }.map { CGWindowID($0.window.windowNumber) })
        let layerZeroInPlace = front.map { Self.isDirectlyBelow($0, layer: layerZero, in: windows) } ?? true
        for level in wanted.indices where wanted[level] != anchors[level] || (level == 0 && !layerZeroInPlace) {
            anchors[level] = wanted[level]
            for overlay in overlays where overlay.level == level {
                guard let anchor = wanted[level] else {
                    Self.fade(overlay.window, to: 0) { [weak self] in
                        if self?.anchors[safe: level] == .some(nil) { overlay.window.orderOut(nil) }  // still unwanted
                    }
                    continue
                }
                // Layer 0 goes under the focused window; deeper layers go over the stale window.
                overlay.window.order(level == 0 ? .below : .above, relativeTo: Int(anchor))
                Self.fade(overlay.window, to: alpha(for: level))
            }
        }

        let newHoles = clearWindowRects(in: windows)
        if newHoles != holes {
            holes = newHoles
            applyMasks()
        }
    }

    /// For each threshold, the front-most window below `front` that has gone untouched at least that long.
    /// shortcut: everything under that window gets the extra layer too, even if it was used more recently;
    /// fine because macOS stacks windows roughly by when you last used them.
    nonisolated static func deepAnchors(stack: [CGWindowID], front: CGWindowID, thresholds: [TimeInterval],
                                        age: (CGWindowID) -> TimeInterval) -> [CGWindowID?] {
        let below = stack.drop { $0 != front }.dropFirst()
        return thresholds.map { t in below.first { age($0) >= t } }
    }

    /// Whether the window right after `front` in the front-to-back list is one of `layer`'s windows.
    nonisolated static func isDirectlyBelow(_ front: CGWindowID, layer: Set<CGWindowID>, in windows: [WindowInfo]) -> Bool {
        guard let i = windows.firstIndex(where: { $0.id == front }), i + 1 < windows.count else { return false }
        return layer.contains(windows[i + 1].id)
    }

    /// IDs of visible normal windows, front to back, leaving out `pid`'s own.
    nonisolated static func visibleWindows(in windows: [WindowInfo], excluding pid: pid_t) -> [CGWindowID] {
        windows.filter { $0.isNormal && $0.isVisible && $0.pid != pid }.map(\.id)
    }

    /// Eases a layer in or out, the way system overlays appear rather than snapping.
    private static func fade(_ window: NSWindow, to alpha: Double, then done: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = alpha > window.alphaValue ? 0.5 : 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { done?() }
        }
    }

    // shortcut: deeper layers at 60% of the depth each, over a 35% black dim; tune by eye.
    private func alpha(for level: Int) -> Double { level == 0 ? depth : depth * 0.6 }

    /// Global top-left-origin bounds of every normal window owned by an Always clear app.
    private func clearWindowRects(in windows: [WindowInfo]) -> [CGRect] {
        guard !clearApps.isEmpty else { return [] }
        // One lookup per tick instead of a LaunchServices call per window.
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier.map(clearApps.contains) ?? false }
            .map(\.processIdentifier))
        return windows.compactMap { w in w.isNormal && pids.contains(w.pid) ? w.bounds : nil }
    }

    /// Cuts Always clear windows out of every layer: an image mask for the blur, a shape mask for dims.
    private func applyMasks() {
        for overlay in overlays {
            let cutouts = holeRects(on: overlay.screenFrame)
            let bounds = NSRect(origin: .zero, size: overlay.screenFrame.size)
            if let blur = overlay.view as? NSVisualEffectView {
                blur.maskImage = cutouts.isEmpty ? nil : NSImage(size: bounds.size, flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.fill()
                    cutouts.forEach { $0.fill(using: .clear) }
                    return true
                }
            } else {
                let shape = CAShapeLayer()
                let holesPath = CGMutablePath()
                holesPath.addRects(cutouts)
                shape.path = CGPath(rect: bounds, transform: nil).subtracting(holesPath)
                overlay.view.layer?.mask = cutouts.isEmpty ? nil : shape
            }
        }
    }

    // shortcut: a hole shows everything under the overlay in that rect, including parts of other
    // windows stacked above the clear window; fine while clear apps are usually side by side.
    /// Always clear windows on this screen, in the screen's own bottom-left coordinates.
    private func holeRects(on screenFrame: NSRect) -> [NSRect] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let screen = NSRect(origin: .zero, size: screenFrame.size)
        return (holes ?? [])
            .map { Self.localRect($0, screenFrame: screenFrame, primaryHeight: primaryHeight) }
            .filter { $0.intersects(screen) }
    }

    /// Converts CGWindowList bounds (global, top-left origin) into a screen's own bottom-left coordinates.
    nonisolated static func localRect(_ cg: CGRect, screenFrame: NSRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: cg.minX - screenFrame.minX,
               y: primaryHeight - cg.maxY - screenFrame.minY,
               width: cg.width, height: cg.height)
    }

    /// The front-most visible normal window owned by `pid`. `windows` is front to back.
    nonisolated static func topWindow(in windows: [WindowInfo], pid: pid_t) -> CGWindowID? {
        windows.first { $0.pid == pid && $0.isNormal && $0.isVisible }?.id
    }

    private func makeOverlay(for screen: NSScreen, level: Int) -> Overlay {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.alphaValue = 0  // fades in when first placed

        let view: NSView
        if level == 0 {
            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            view = blur
        } else {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        }
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        return Overlay(window: window, view: view, screenFrame: screen.frame, level: level)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
