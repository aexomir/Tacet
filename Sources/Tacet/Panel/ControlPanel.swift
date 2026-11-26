import SwiftUI

/// The menu bar circle: hollow when off, filling up with depth.
func levelGlyph(isOn: Bool, depth: Double) -> String {
    guard isOn else { return "○" }
    return depth < 0.45 ? "◔" : depth < 0.75 ? "◑" : "●"
}

private func levelName(isOn: Bool, depth: Double) -> String {
    guard isOn else { return "Off" }
    return depth < 0.45 ? "Light" : depth < 0.75 ? "Medium" : "Deep"
}

/// Control Center–style Liquid Glass panel: power tile, Depth slider, Always clear apps.
struct ControlPanel: View {
    @Binding var isOn: Bool
    @Binding var depth: Double
    @Binding var clearApps: [String]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                powerTile
                depthTile
                clearTile
            }
        }
        .padding(12)
        .frame(width: 290)
    }

    private var powerTile: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                Text(levelGlyph(isOn: isOn, depth: depth))
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .glassEffect(isOn ? .regular.tint(.primary) : .regular, in: .circle)
                    .foregroundStyle(isOn ? Color(nsColor: .windowBackgroundColor) : .primary)
                VStack(alignment: .leading) {
                    Text("Tacet").font(.headline)
                    Text(levelName(isOn: isOn, depth: depth)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var depthTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depth").font(.subheadline.weight(.medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: max(30, geo.size.width * depth))
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
                    depth = min(1, max(0.2, g.location.x / geo.size.width))
                })
            }
            .frame(height: 30)
            .accessibilityElement()
            .accessibilityLabel("Depth")
            .accessibilityValue(levelName(isOn: true, depth: depth))
            .accessibilityAdjustableAction { dir in
                depth = min(1, max(0.2, depth + (dir == .increment ? 0.1 : -0.1)))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var clearTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always clear").font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(clearApps, id: \.self) { id in
                    AppIcon(bundleID: id)
                        .contextMenu { Button("Remove") { clearApps.removeAll { $0 == id } } }
                }
                Menu {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { clearApps.append(id) }
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
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier.map { !clearApps.contains($0) } ?? false }
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
