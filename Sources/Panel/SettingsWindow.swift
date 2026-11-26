import AppKit
import ServiceManagement
import SwiftUI

/// A standard macOS settings window for the tuning values.
@MainActor
final class SettingsWindow {
    private let window: NSWindow

    init(state: TacetState) {
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
        window.title = "Tacet Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
    }

    func show() {
        if !window.isVisible { window.center() }
        NSApp.activate()  // a menu bar app has to bring itself forward for its window to take focus
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @Bindable var state: TacetState
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginStatus == .enabled }, set: setOpensAtLogin))
                if loginStatus == .requiresApproval {
                    LabeledContent("Allow Tacet in Login Items to finish turning this on.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section {
                stepper("Blur after settling in for", $state.tuning.settleAfter, 5...120, step: 5, unit: "s")
                stepper("If you typed or scrolled within", $state.tuning.recentInput, 1...30, step: 1, unit: "s")
                Stepper(value: $state.tuning.hopsToLift, in: 2...8) {
                    LabeledContent("Lift after switching apps", value: "\(state.tuning.hopsToLift) times")
                }
                stepper("Within", $state.tuning.hopWindow, 5...60, step: 5, unit: "s")
            } header: {
                Text("Auto-focus")
            } footer: {
                Text("Blur comes on once you settle into one app, and lifts when you hop between apps.")
                    .foregroundStyle(.secondary)
            }

            Section("Windows you leave alone") {
                stepper("Darken after", $state.tuning.darkenAfterMinutes, 1...120, step: 1, unit: "min")
                stepper("Darken more after", $state.tuning.darkenMoreAfterMinutes,
                        (state.tuning.darkenAfterMinutes + 1)...240, step: 5, unit: "min")
                LabeledContent("Darkness") {
                    Slider(value: $state.tuning.darkness, in: 0.1...0.7)
                        .frame(width: 180)
                    Text(state.tuning.darkness, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { state.tuning = Tuning() }
                        .disabled(state.tuning == Tuning())
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // Keep the second step after the first when the first moves past it.
        .onChange(of: state.tuning.darkenAfterMinutes) { _, first in
            if state.tuning.darkenMoreAfterMinutes <= first { state.tuning.darkenMoreAfterMinutes = first + 1 }
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            loginError = nil
        } catch {
            // Fails when Tacet runs from the terminal (swift run) rather than as an installed app.
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func stepper(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                         step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(label, value: "\(Int(value.wrappedValue)) \(unit)")
        }
    }
}
