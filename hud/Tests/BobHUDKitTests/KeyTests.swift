import Foundation
import Testing

@testable import BobHUDKit

@Suite("The globe key")
struct KeyTests {
    /// Presses at the given seconds after a start, each released before
    /// the next, and whether each one closed a pair.
    private func doubles(_ seconds: [TimeInterval], interval: TimeInterval = 0.5) -> [Bool] {
        var taps = DoubleTap(interval: interval)
        let start = Date()
        return seconds.map { offset in
            let double = taps.press(at: start.addingTimeInterval(offset))
            taps.release()
            return double
        }
    }

    @Test("two quick presses are a double, and the pair is then spent")
    func double() {
        // The third press starts a new pair rather than closing the old one.
        #expect(doubles([0, 0.3, 0.5, 0.8]) == [false, true, false, true])
    }

    @Test("a hold and then a press is not a double")
    func hold() {
        #expect(doubles([0, 0.6]) == [false, false])
        // A two-second hold, then a press soon after the release: the
        // interval runs from the first down, so this is not a pair either.
        #expect(doubles([0, 2.1]) == [false, false])
    }

    @Test("another modifier changing under the held key is not a press")
    func modifierUnderHold() {
        var taps = DoubleTap(interval: 0.5)
        let start = Date()
        let first = taps.press(at: start)
        // Shift went down while the globe was still held: flagsChanged
        // fires again with the globe flag still set.
        let shift = taps.press(at: start.addingTimeInterval(0.2))
        taps.release()
        let second = taps.press(at: start.addingTimeInterval(0.4))
        #expect(!first && !shift && second)
    }
}
