import SwiftUI

@main
struct TacetApp: App {
    @State private var isOn = true
    @AppStorage("depth") private var depth = 0.8
    // Bundle IDs joined by newlines: AppStorage has no array type.
    @AppStorage("clearApps") private var clearAppsRaw = ""
    private let engine = BlurEngine()

    init() {
        // Menu bar only: no Dock icon. shortcut: set in code until there's an Info.plist with LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
        // Prototype starts with the blur on; Auto-focus will decide this later.
        DispatchQueue.main.async { [engine, depth, clearAppsRaw] in
            engine.depth = depth
            engine.clearApps = Set(clearAppsRaw.split(separator: "\n").map(String.init))
            engine.start()
        }
    }

    private var clearApps: Binding<[String]> {
        Binding(
            get: { clearAppsRaw.split(separator: "\n").map(String.init) },
            set: { clearAppsRaw = $0.joined(separator: "\n") }
        )
    }

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(isOn: $isOn, depth: $depth, clearApps: clearApps)
                .onChange(of: isOn) { _, on in on ? engine.start() : engine.stop() }
                .onChange(of: depth) { _, d in engine.depth = d }
                .onChange(of: clearAppsRaw) { _, raw in
                    engine.clearApps = Set(raw.split(separator: "\n").map(String.init))
                }
                .contextMenu { Button("Quit Tacet") { NSApplication.shared.terminate(nil) } }
        } label: {
            Text(levelGlyph(isOn: isOn, depth: depth))
        }
        .menuBarExtraStyle(.window)
    }
}
