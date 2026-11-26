import CoreGraphics
import Testing
@testable import Tacet

@Test func convertsWindowBoundsToScreenLocalRect() {
    // Primary screen 1512x982 at origin; external 1920x1080 to its right, bottoms aligned.
    let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    // A 400x300 window 100pt from the external screen's left edge, 50pt below the top of the
    // primary screen's top edge in CG coordinates (external top sits at CG y = 982 - 1080 = -98).
    let cg = CGRect(x: 1612, y: 50, width: 400, height: 300)
    let local = BlurEngine.localRect(cg, screenFrame: external, primaryHeight: 982)
    #expect(local == CGRect(x: 100, y: 982 - 350, width: 400, height: 300))
    // Same window on the primary screen.
    let onPrimary = BlurEngine.localRect(CGRect(x: 10, y: 20, width: 100, height: 100),
                                         screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                         primaryHeight: 982)
    #expect(onPrimary == CGRect(x: 10, y: 862, width: 100, height: 100))
}

@Test func picksFrontMostNormalWindowOfApp() {
    func win(_ id: CGWindowID, pid: pid_t, layer: Int, alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
         kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha]
    }
    let list = [
        win(1, pid: 50, layer: 0),   // another app's window in front
        win(2, pid: 42, layer: 25),  // our app's menu bar item / panel layer
        win(5, pid: 42, layer: 0, alpha: 0),  // invisible helper window web apps keep in front
        win(3, pid: 42, layer: 0),   // the focused document window
        win(4, pid: 42, layer: 0),   // a window behind it
    ].compactMap(WindowInfo.init)
    #expect(BlurEngine.topWindow(in: list, pid: 42) == 3)
    #expect(BlurEngine.topWindow(in: list, pid: 99) == nil)
}
