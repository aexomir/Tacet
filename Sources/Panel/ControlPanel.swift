import SwiftUI

/// 0 = off, then 1...3 as depth goes from light to deep.
private func level(isOn: Bool, depth: Double) -> Int {
    !isOn ? 0 : depth < 0.45 ? 1 : depth < 0.75 ? 2 : 3
}

/// How full the dial is: empty when off, then a quarter at the lightest depth up to full.
func dialFraction(isOn: Bool, depth: Double) -> Double {
    isOn ? 0.25 + (depth - 0.2) / 0.8 * 0.75 : 0
}

/// Ring with a pie that fills from 12 o'clock; animates smoothly between fractions.
private struct Dial: View {
    var fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.5)
            Wedge(fraction: fraction).padding(3)
        }
    }

    private struct Wedge: Shape {
        var fraction: Double
        var animatableData: Double {
            get { fraction }
            set { fraction = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard fraction > 0.001 else { return path }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

private func levelName(isOn: Bool, depth: Double) -> String {
    ["Off", "Light", "Medium", "Deep"][level(isOn: isOn, depth: depth)]
}

/// Control Center–style Liquid Glass panel: power and Auto-focus tiles, Depth slider, Always clear apps.
struct ControlPanel: View {
    let state: TacetState
    let presentation: PanelPresentation

    private let tileSpring = Animation.spring(response: 0.3, dampingFraction: 0.75)
    private let plannerAvailable = FocusPlanner.isAvailable

    @State private var task = ""
    @State private var isPlanning = false
    @State private var outcome: String?
    @State private var canUndo = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if plannerAvailable { intentTile }
                HStack(spacing: 10) {
                    powerTile
                    autoFocusTile
                }
                depthTile
                clearTile
                settingsButton
            }
        }
        .animation(tileSpring, value: state.isOn)
        .animation(tileSpring, value: state.autoFocusOn)
        .animation(tileSpring, value: state.clearApps)
        // Springs down out of the menu bar like Control Center, and shrinks back on close.
        .scaleEffect(presentation.isOpen ? 1 : 0.9, anchor: .topTrailing)
        .opacity(presentation.isOpen ? 1 : 0)
        .padding(12)  // room for the glass shadow inside the transparent panel
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presentation.onHeightChange($0) }
        .frame(width: 314)
    }

    // "What are you working on?" → on-device model picks the apps to keep clear and the depth.
    private var intentTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: isPlanning)
                    .accessibilityHidden(true)
                TextField("What are you working on?", text: $task)
                    .textFieldStyle(.plain)
                    .onSubmit(plan)
                    .disabled(isPlanning)
                if isPlanning { ProgressView().controlSize(.small) }
            }
            if let outcome {
                HStack(alignment: .firstTextBaseline) {
                    Text(outcome).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if canUndo {
                        Button("Undo") {
                            withAnimation(tileSpring) {
                                state.undoPlan()
                                self.outcome = nil
                                canUndo = false
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func plan() {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPlanning else { return }
        task = ""
        isPlanning = true
        Task {
            do {
                let plan = try await FocusPlanner.plan(for: text)
                withAnimation(tileSpring) {
                    state.apply(plan)
                    let names = ListFormatter.localizedString(byJoining: plan.apps.map(\.name))
                    outcome = "Keeping \(names) clear · \(levelName(isOn: true, depth: plan.depth))"
                    canUndo = true
                }
            } catch {
                withAnimation(tileSpring) {
                    outcome = error.localizedDescription
                    canUndo = false
                }
            }
            isPlanning = false
        }
    }

    private var powerTile: some View {
        Button { state.isOn.toggle() } label: {
            HStack(spacing: 12) {
                Dial(fraction: dialFraction(isOn: state.isOn, depth: state.depth))
                    .frame(width: 18, height: 18)
                    .frame(width: 40, height: 40)
                    .glassEffect(state.isOn ? .regular.tint(.primary) : .regular, in: .circle)
                    .foregroundStyle(state.isOn ? Color(nsColor: .windowBackgroundColor) : .primary)
                VStack(alignment: .leading) {
                    Text("Tacet").font(.headline)
                    Text(levelName(isOn: state.isOn, depth: state.depth))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var autoFocusTile: some View {
        Button { state.autoFocusOn.toggle() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolEffect(.bounce, value: state.autoFocusOn)
                    .frame(width: 30, height: 30)
                    .glassEffect(state.autoFocusOn ? .regular.tint(.primary) : .regular, in: .circle)
                    .foregroundStyle(state.autoFocusOn ? Color(nsColor: .windowBackgroundColor) : .primary)
                Text("Auto-focus").font(.subheadline.weight(.medium))
            }
            .padding(12)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .help("Blurs when you settle into one app; lifts when you hop between apps")
        .accessibilityValue(state.autoFocusOn ? "On" : "Off")
    }

    private var depthTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depth").font(.subheadline.weight(.medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(30, geo.size.width * state.depth))
                    HStack {
                        Image(systemName: "circle").foregroundStyle(.black)
                        Spacer()
                        Image(systemName: "circle.fill")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                }
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
                .contentShape(.capsule)
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    state.depth = min(1, max(0.2, g.location.x / geo.size.width))
                })
            }
            .frame(height: 30)
            .accessibilityElement()
            .accessibilityLabel("Depth")
            .accessibilityValue(levelName(isOn: true, depth: state.depth))
            .accessibilityAdjustableAction { dir in
                state.depth = min(1, max(0.2, state.depth + (dir == .increment ? 0.1 : -0.1)))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var clearTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always clear").font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(state.clearApps, id: \.self) { id in
                    AppIcon(bundleID: id)
                        .transition(.scale.combined(with: .opacity))
                        .contextMenu { Button("Remove") { state.clearApps.removeAll { $0 == id } } }
                }
                Menu {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { state.clearApps.append(id) }
                        }
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Add app")
                Spacer()
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // Like Control Center's "Edit Controls" pill under the tiles.
    private var settingsButton: some View {
        Button("Tacet Settings…") { presentation.openSettings() }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var addableApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier.map { !state.clearApps.contains($0) } ?? false }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
            .resizable()
            .frame(width: 30, height: 30)
            .help(url?.deletingPathExtension().lastPathComponent ?? bundleID)
            .accessibilityLabel(url?.deletingPathExtension().lastPathComponent ?? bundleID)
    }
}
