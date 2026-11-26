import AppKit

/// Covers every screen with a click-through blur window ordered directly below the focused window.
/// macOS draws the blur (NSVisualEffectView, behind-window blending), so no Screen Recording permission.
@MainActor
final class BlurEngine {
    var depth: Double = 0.8 {
        didSet { overlays.forEach { $0.window.alphaValue = depth } }
    }

    /// Bundle IDs whose windows are cut out of the blur.
    var clearApps: Set<String> = [] {
        didSet { holes = []; refresh() }
    }

    private struct Overlay {
        let window: NSWindow
        let blur: NSVisualEffectView
        let screenFrame: NSRect
    }

    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var target: CGWindowID = 0
    private var holes: [CGRect] = []

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
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = []
        target = 0
        holes = []
    }

    private func refresh() {
        // While Tacet's own panel is in front, leave the blur where it is.
        guard isOn, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let front = Self.topWindow(in: list, pid: app.processIdentifier) else {
            overlays.forEach { $0.window.orderOut(nil) }
            target = 0
            return
        }
        if front != target {
            target = front
            overlays.forEach { $0.window.order(.below, relativeTo: Int(front)) }
        }
        let newHoles = clearWindowRects(in: list)
        if newHoles != holes {
            holes = newHoles
            overlays.forEach { applyMask($0) }
        }
    }

    /// Global top-left-origin bounds of every normal window owned by an Always clear app.
    private func clearWindowRects(in list: [[String: Any]]) -> [CGRect] {
        guard !clearApps.isEmpty else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  clearApps.contains(id),
                  let b = w[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: b)
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

    /// The front-most visible normal window owned by `pid`. `list` is CGWindowList output, front to back.
    /// Skips fully transparent windows: web apps (PWAs) keep an invisible one in front of the real one.
    nonisolated static func topWindow(in list: [[String: Any]], pid: pid_t) -> CGWindowID? {
        list.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
                && (($0[kCGWindowAlpha as String] as? Double) ?? 1) > 0
        }?[kCGWindowNumber as String] as? CGWindowID
    }

    private func makeOverlay(for screen: NSScreen) -> Overlay {
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
        let overlay = Overlay(window: window, blur: blur, screenFrame: screen.frame)
        applyMask(overlay)
        return overlay
    }
}
