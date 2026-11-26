import AppKit

/// Covers every screen with a click-through blur window ordered directly below the focused window.
/// macOS draws the blur (NSVisualEffectView, behind-window blending), so no Screen Recording permission.
@MainActor
final class BlurEngine {
    var depth: Double = 0.8 {
        didSet { overlays.forEach { $0.alphaValue = depth } }
    }

    private var overlays: [NSWindow] = []
    private var timer: Timer?
    private var target: CGWindowID = 0

    var isOn: Bool { !overlays.isEmpty }

    func start() {
        guard !isOn else { return }
        overlays = NSScreen.screens.map(makeOverlay)
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
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        target = 0
    }

    private func refresh() {
        // While Tacet's own panel is in front, leave the blur where it is.
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let front = Self.topWindow(in: list, pid: app.processIdentifier) else {
            overlays.forEach { $0.orderOut(nil) }
            target = 0
            return
        }
        guard front != target else { return }
        target = front
        overlays.forEach { $0.order(.below, relativeTo: Int(front)) }
    }

    /// The front-most normal window owned by `pid`. `list` is CGWindowList output, front to back.
    nonisolated static func topWindow(in list: [[String: Any]], pid: pid_t) -> CGWindowID? {
        list.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    private func makeOverlay(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.alphaValue = depth

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        window.contentView = blur
        window.setFrame(screen.frame, display: false)
        return window
    }
}
