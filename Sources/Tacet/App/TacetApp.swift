import SwiftUI

@main
struct TacetApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }  // all UI lives in the status item panel
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon. shortcut: set in code until there's an Info.plist with LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        statusItem = StatusItemController(state: TacetState())
    }
}
