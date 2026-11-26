import SwiftUI

@main
struct TacetApp: App {
    @State private var state = TacetState()

    init() {
        // Menu bar only: no Dock icon. shortcut: set in code until there's an Info.plist with LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(state: state)
                .contextMenu { Button("Quit Tacet") { NSApplication.shared.terminate(nil) } }
        } label: {
            Text(levelGlyph(isOn: state.isOn, depth: state.depth))
        }
        .menuBarExtraStyle(.window)
    }
}
