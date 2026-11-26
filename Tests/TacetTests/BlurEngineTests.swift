import CoreGraphics
import Testing
@testable import Tacet

@Test func picksFrontMostNormalWindowOfApp() {
    func win(_ id: CGWindowID, pid: pid_t, layer: Int) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer]
    }
    let list = [
        win(1, pid: 50, layer: 0),   // another app's window in front
        win(2, pid: 42, layer: 25),  // our app's menu bar item / panel layer
        win(3, pid: 42, layer: 0),   // the focused document window
        win(4, pid: 42, layer: 0),   // a window behind it
    ]
    #expect(BlurEngine.topWindow(in: list, pid: 42) == 3)
    #expect(BlurEngine.topWindow(in: list, pid: 99) == nil)
}
