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

/// Covers every screen with click-through blur windows. The first layer sits directly below the
/// focused window; extra layers sit above windows you haven't touched in a while, so blur
/// deepens with neglect. macOS draws the blur (NSVisualEffectView, behind-window blending),
/// so no Screen Recording permission.
@MainActor
final class BlurEngine {
    var depth: Double = 0.8 {
        didSet { overlays.forEach { $0.window.alphaValue = alpha(for: $0.level) } }
    }

    /// Bundle IDs whose windows are cut out of the blur.
    var clearApps: Set<String> = [] {
        didSet { holes = []; refresh() }
    }

    /// A window untouched this long gets one more blur layer on top of it, per entry.
    static let deepenAfter: [TimeInterval] = [5 * 60, 30 * 60]

    private struct Overlay {
        let window: NSWindow
        let blur: NSVisualEffectView
        let screenFrame: NSRect
        let level: Int  // 0 = below the focused window, 1... = deeper layers
    }

    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var anchors: [CGWindowID?] = []  // per level: the window each layer is placed against
    private var holes: [CGRect] = []
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
        // shortcut: polls the window list 4x a second because tracking window focus inside an app
        // without Accessibility has no notification; replace if it shows up in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = []
        anchors = []
        holes = []
        lastFocused = [:]
    }

    private func refresh() {
        // While Tacet's own panel is in front, leave the blur where it is.
        guard isOn, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return }
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap(WindowInfo.init)
        let now = ProcessInfo.processInfo.systemUptime
        let stack = Self.visibleWindows(in: windows, excluding: getpid())
        let front = Self.topWindow(in: windows, pid: app.processIdentifier)
        if let front { lastFocused[front] = now }
        lastFocused = lastFocused.filter { stack.contains($0.key) }

        let deep = front.map { front in
            Self.deepAnchors(stack: stack, front: front, thresholds: Self.deepenAfter) {
                now - (self.lastFocused[$0] ?? self.startedAt)
            }
        } ?? []
        let wanted = [front] + (deep.isEmpty ? Array(repeating: nil, count: Self.deepenAfter.count) : deep)
        for level in wanted.indices where wanted[level] != anchors[level] {
            anchors[level] = wanted[level]
            for overlay in overlays where overlay.level == level {
                guard let anchor = wanted[level] else { overlay.window.orderOut(nil); continue }
                // Layer 0 goes under the focused window; deeper layers go over the stale window.
                overlay.window.order(level == 0 ? .below : .above, relativeTo: Int(anchor))
            }
        }

        let newHoles = clearWindowRects(in: windows)
        if newHoles != holes {
            holes = newHoles
            overlays.forEach { applyMask($0) }
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

    /// IDs of visible normal windows, front to back, leaving out `pid`'s own.
    nonisolated static func visibleWindows(in windows: [WindowInfo], excluding pid: pid_t) -> [CGWindowID] {
        windows.filter { $0.isNormal && $0.isVisible && $0.pid != pid }.map(\.id)
    }

    // shortcut: deeper layers at 60% strength each; tune by eye.
    private func alpha(for level: Int) -> Double { level == 0 ? depth : depth * 0.6 }

    /// Global top-left-origin bounds of every normal window owned by an Always clear app.
    private func clearWindowRects(in windows: [WindowInfo]) -> [CGRect] {
        guard !clearApps.isEmpty else { return [] }
        return windows.compactMap { w in
            guard w.isNormal, let id = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier,
                  clearApps.contains(id) else { return nil }
            return w.bounds
        }
    }

    // shortcut: a hole shows everything under the overlay in that rect, including parts of other
    // windows stacked above the clear window; fine while clear apps are usually side by side.
    private func applyMask(_ overlay: Overlay) {
        guard !holes.isEmpty else { overlay.blur.maskImage = nil; return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? overlay.screenFrame.height
        let local = holes.map { Self.localRect($0, screenFrame: overlay.screenFrame, primaryHeight: primaryHeight) }
        overlay.blur.maskImage = NSImage(size: overlay.screenFrame.size, flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            local.forEach { $0.fill(using: .clear) }
            return true
        }
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
        window.alphaValue = alpha(for: level)

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        window.contentView = blur
        window.setFrame(screen.frame, display: false)
        let overlay = Overlay(window: window, blur: blur, screenFrame: screen.frame, level: level)
        applyMask(overlay)
        return overlay
    }
}
