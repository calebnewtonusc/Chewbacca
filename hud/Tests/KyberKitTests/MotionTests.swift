import SwiftUI
import Testing
@testable import KyberKit

@Suite("Motion")
@MainActor
struct MotionTests {
    @Test("inside the screen a drag follows the hand exactly")
    func dragIsOneToOne() {
        let range: ClosedRange<CGFloat> = -300...300
        for value in stride(from: CGFloat(-300), through: 300, by: 37.5) {
            #expect(OverlayModel.resist(value, within: range) == value)
        }
    }

    @Test("past the edge a drag keeps moving, a third as far")
    func dragResistsAtTheEdge() {
        let range: ClosedRange<CGFloat> = -100...100
        let past = OverlayModel.resist(160, within: range)
        #expect(past > 100, "the card stopped dead at the edge")
        #expect(past < 160, "the card ignored the edge")
        #expect(abs(past - (100 + 60 * OverlayModel.resistance)) < 0.001)
        #expect(OverlayModel.resist(-160, within: range) < -100)
        // Monotonic: moving the hand further never moves the card back.
        var last = -CGFloat.infinity
        for value in stride(from: CGFloat(-400), through: 400, by: 10) {
            let now = OverlayModel.resist(value, within: range)
            #expect(now > last)
            last = now
        }
    }

    @Test("every named motion stands still under Reduce Motion")
    func tokensHonourReduceMotion() {
        // Reduced, a spring becomes a 0.12 s fade and a fade is capped at
        // 0.1 s: nothing travels. The check is that none of them hands back
        // the full animation it would give otherwise.
        #expect(Motion.snappy(reduced: true) != Motion.snappy(reduced: false))
        #expect(Motion.smooth(reduced: true) != Motion.smooth(reduced: false))
        #expect(Motion.gentle(reduced: true) != Motion.gentle(reduced: false))
        #expect(Motion.repeating(.linear, reduced: true) == nil)
    }
}
