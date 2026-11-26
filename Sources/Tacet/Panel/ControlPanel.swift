import SwiftUI

/// 0 = off, then 1...3 as depth goes from light to deep.
private func level(isOn: Bool, depth: Double) -> Int {
    !isOn ? 0 : depth < 0.45 ? 1 : depth < 0.75 ? 2 : 3
}

/// The menu bar circle: hollow when off, filling up with depth.
func levelGlyph(isOn: Bool, depth: Double) -> String {
    ["○", "◔", "◑", "●"][level(isOn: isOn, depth: depth)]
}

private func levelName(isOn: Bool, depth: Double) -> String {
    ["Off", "Light", "Medium", "Deep"][level(isOn: isOn, depth: depth)]
}

/// Control Center–style Liquid Glass panel: power and Auto-focus tiles, Depth slider, Always clear apps.
struct ControlPanel: View {
    let state: TacetState

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    powerTile
                    autoFocusTile
                }
                depthTile
                clearTile
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    private var powerTile: some View {
        Button { state.isOn.toggle() } label: {
            HStack(spacing: 12) {
                Text(levelGlyph(isOn: state.isOn, depth: state.depth))
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .glassEffect(state.isOn ? .regular.tint(.primary) : .regular, in: .circle)
                    .foregroundStyle(state.isOn ? Color(nsColor: .windowBackgroundColor) : .primary)
                VStack(alignment: .leading) {
                    Text("Tacet").font(.headline)
                    Text(levelName(isOn: state.isOn, depth: state.depth)).font(.subheadline).foregroundStyle(.secondary)
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
                        Text("○").foregroundStyle(.black)
                        Spacer()
                        Text("●")
                    }
                    .font(.system(size: 13))
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
