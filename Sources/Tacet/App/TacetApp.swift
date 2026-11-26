import SwiftUI

@main
struct TacetApp: App {
    init() {
        // Menu bar only: no Dock icon. shortcut: set in code until there's an Info.plist with LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Tacet")
                .padding()
        } label: {
            Text("○")
        }
        .menuBarExtraStyle(.window)
    }
}
