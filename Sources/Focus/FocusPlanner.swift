import AppKit
import FoundationModels

/// Turns "what are you working on?" into a focus setup with Apple's on-device model.
/// The model only sees the names of running apps and the sentence typed; nothing leaves the Mac.
enum FocusPlanner {
    struct Plan {
        var apps: [(name: String, bundleID: String)]
        var depth: Double
    }

    enum Failure: LocalizedError {
        case noMatch
        var errorDescription: String? { "None of your open apps fit that. Open what you need and try again." }
    }

    /// False on Intel Macs, or when Apple Intelligence is off or still downloading.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    @MainActor
    static func plan(for task: String) async throws -> Plan {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in app.localizedName.flatMap { name in app.bundleIdentifier.map { (name, $0) } } }

        let session = LanguageModelSession(instructions: """
            You set up a focus session on a Mac. From the running apps listed, pick only the ones the \
            person needs for their task; everything else will be blurred. Leave out Finder, chat, email, \
            music and social apps unless the task is about them. Copy app names exactly as listed.
            """)
        let answer = try await session.respond(
            to: "Running apps: \(running.map(\.0).joined(separator: ", "))\nTask: \(task)",
            generating: Answer.self
        ).content

        let apps = match(answer.apps, in: running)
        guard !apps.isEmpty else { throw Failure.noMatch }
        return Plan(apps: apps, depth: answer.depth.value)
    }

    /// Display name for an app the person added to a query by hand.
    @MainActor
    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName ?? bundleID
    }

    /// Maps the model's app names back to running apps: exact match first, then whole-word containment
    /// either way ("Code" → "Visual Studio Code", but not "Xcode"), ignoring case. Keeps the model's
    /// order, no duplicates.
    nonisolated static func match(_ picked: [String], in running: [(name: String, bundleID: String)])
        -> [(name: String, bundleID: String)] {
        var result: [(name: String, bundleID: String)] = []
        for raw in picked {
            let want = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !want.isEmpty else { continue }
            let wantWords = words(want)
            let hit = running.first { $0.name.lowercased() == want }
                ?? running.first {
                    let nameWords = words($0.name.lowercased())
                    return nameWords.isSuperset(of: wantWords) || wantWords.isSuperset(of: nameWords)
                }
            if let hit, !result.contains(where: { $0.bundleID == hit.bundleID }) { result.append(hit) }
        }
        return result
    }

    private nonisolated static func words(_ s: String) -> Set<Substring> {
        Set(s.split { !$0.isLetter && !$0.isNumber })
    }

    @Generable
    struct Answer {
        @Guide(description: "Running apps the task needs, names copied exactly from the list")
        var apps: [String]
        @Guide(description: "deep for writing, coding or study that needs concentration; light when they must keep glancing at other windows")
        var depth: Depth
    }

    @Generable
    enum Depth {
        case light, medium, deep

        var value: Double {
            switch self {
            case .light: 0.35
            case .medium: 0.6
            case .deep: 0.9
            }
        }
    }
}
