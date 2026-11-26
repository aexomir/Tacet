import AppKit
import SwiftUI

/// Whether the panel's tiles are shown; drives the open and close spring.
@MainActor @Observable
final class PanelPresentation {
    var isOpen = false
    @ObservationIgnored var openSettings: () -> Void = {}
}

/// The menu bar dial and the frameless panel it opens. Replaces MenuBarExtra, whose window
/// always draws its own background behind the tiles.
@MainActor
final class StatusItemController {
    private let state: TacetState
    private let presentation = PanelPresentation()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: GlassPanel
    private let settings: SettingsWindow
    private var clickMonitor: Any?
    private var shownFraction = 0.0
    private var iconTimer: Timer?

    init(state: TacetState) {
        self.state = state
        panel = GlassPanel(content: ControlPanel(state: state, presentation: presentation))
        settings = SettingsWindow(state: state)
        panel.onCancel = { [weak self] in self?.close() }
        presentation.openSettings = { [weak self] in self?.showSettings() }

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Tacet")
        }
        shownFraction = dialFraction(isOn: state.isOn, depth: state.depth)
        item.button?.image = Self.dialImage(fraction: shownFraction)
        watchState()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Tacet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            // Attach the menu only for this click so a left click still opens the panel.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            presentation.isOpen ? close() : open()
        }
    }

    @objc private func showSettings() {
        close()
        settings.show()
    }

    private func open() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let size = panel.contentView?.fittingSize ?? .zero
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? .zero
        // Right edge under the icon like Control Center, kept on screen.
        let x = min(max(anchor.maxX - size.width + 12, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { presentation.isOpen = true }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        guard presentation.isOpen else { return }
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
        withAnimation(.easeOut(duration: 0.16)) {
            presentation.isOpen = false
        } completion: { [weak self] in
            guard let self, !presentation.isOpen else { return }
            panel.orderOut(nil)
        }
    }

    /// Re-runs whenever isOn or depth change and slides the dial to the new fill.
    private func watchState() {
        withObservationTracking {
            _ = (state.isOn, state.depth)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.animateDial(to: dialFraction(isOn: self.state.isOn, depth: self.state.depth))
                self.watchState()
            }
        }
    }

    private func animateDial(to target: Double) {
        iconTimer?.invalidate()
        let start = shownFraction, began = CACurrentMediaTime(), duration = 0.25
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min(1, (CACurrentMediaTime() - began) / duration)
                let eased = 1 - pow(1 - t, 3)
                self.shownFraction = start + (target - start) * eased
                self.item.button?.image = Self.dialImage(fraction: self.shownFraction)
                if t >= 1 { self.iconTimer?.invalidate() }
            }
        }
    }

    /// A ring that fills like a pie from 12 o'clock; template so it follows the menu bar's color.
    private static func dialImage(fraction: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let ring = rect.insetBy(dx: 1.5, dy: 1.5)
            let outline = NSBezierPath(ovalIn: ring)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()
            guard fraction > 0.001 else { return true }
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: ring.width / 2 - 2, startAngle: 90,
                            endAngle: 90 - 360 * fraction, clockwise: true)
            wedge.close()
            NSColor.black.setFill()
            wedge.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Borderless, transparent, non-activating panel: only the glass tiles show, and opening it
/// doesn't take focus from the app you're working in (so Auto-focus doesn't count it as a switch).
private final class GlassPanel: NSPanel {
    var onCancel: () -> Void = {}

    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // the glass draws its own
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { true }  // so Esc reaches cancelOperation
    override func cancelOperation(_ sender: Any?) { onCancel() }
}
