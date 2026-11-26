import Testing
@testable import Tacet

private let running = [
    (name: "Xcode", bundleID: "com.apple.dt.Xcode"),
    (name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
    (name: "Notes", bundleID: "com.apple.Notes"),
    (name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
]

@Test func matchesModelNamesToRunningApps() {
    let ids = FocusPlanner.match([" xcode ", "Code", "notes", "Notes", "Photoshop", ""], in: running).map(\.bundleID)
    // case and spaces ignored, "Code" finds VS Code, duplicates and unknown apps dropped, order kept
    #expect(ids == ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.Notes"])
}

@Test func exactNameWinsOverPartialMatch() {
    let apps = [(name: "Notes Helper", bundleID: "a"), (name: "Notes", bundleID: "b")]
    #expect(FocusPlanner.match(["Notes"], in: apps).map(\.bundleID) == ["b"])
}
