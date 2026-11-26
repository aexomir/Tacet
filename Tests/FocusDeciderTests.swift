import Foundation
import Testing
@testable import Tacet

@Test func blursOnlyAfterSettlingWithRecentInput() {
    var d = FocusDecider(now: 0)
    #expect(d.decide(now: 10, idle: 1) == nil)    // not settled yet
    #expect(d.decide(now: 25, idle: 30) == nil)   // settled but away from keyboard
    #expect(d.decide(now: 25, idle: 2) == true)   // settled and typing
}

@Test func hoppingBetweenAppsLiftsThenSettlesAgain() {
    var d = FocusDecider(now: 0)
    d.appChanged(at: 100)
    d.appChanged(at: 103)
    #expect(d.decide(now: 104, idle: 0) == nil)  // two switches: not hopping yet
    d.appChanged(at: 106)
    #expect(d.decide(now: 107, idle: 0) == false) // three in 10s: lift
    #expect(d.decide(now: 117, idle: 0) == nil)   // switches aged out, not settled yet
    #expect(d.decide(now: 126, idle: 0) == true)  // 20s in the last app
}

@Test func usesTunedTimings() {
    var tuning = Tuning()
    tuning.settleAfter = 60
    tuning.hopsToLift = 2
    var d = FocusDecider(now: 0, tuning: tuning)
    #expect(d.decide(now: 30, idle: 0) == nil)    // default 20s would have blurred
    #expect(d.decide(now: 61, idle: 0) == true)
    d.appChanged(at: 70)
    d.appChanged(at: 72)
    #expect(d.decide(now: 73, idle: 0) == false)  // two switches lift with hopsToLift = 2
}

@Test func tuningSurvivesSaving() throws {
    var tuning = Tuning()
    tuning.darkness = 0.5
    let decoded = try JSONDecoder().decode(Tuning.self, from: JSONEncoder().encode(tuning))
    #expect(decoded == tuning)
}
