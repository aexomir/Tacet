import SwiftUI

@main
struct TacetApp: App {
    @State private var isOn = true
    @State private var depth = 0.8
    private let engine = BlurEngine()

    init() {
        // Menu bar only: no Dock icon. shortcut: set in code until there's an Info.plist with LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
        // Prototype starts with the blur on; Auto-focus will decide this later.
        DispatchQueue.main.async { [engine] in engine.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Tacet", isOn: $isOn)
                Slider(value: $depth, in: 0.2...1) { Text("Depth") }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding()
            .frame(width: 240)
            .onChange(of: isOn) { _, on in on ? engine.start() : engine.stop() }
            .onChange(of: depth) { _, d in engine.depth = d }
        } label: {
            Text(isOn ? "◑" : "○")
        }
        .menuBarExtraStyle(.window)
    }
}
