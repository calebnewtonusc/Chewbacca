import Foundation
import Testing
import Vision

@testable import KyberKit

// Swift Testing, not XCTest, and that is not a style choice: `import XCTest`
// does not resolve in this package on Swift 6.1.2, so the whole test run died
// at compile time and took all 177 other tests with it. The failure was hidden
// behind the Portal target's own compile error, which stopped the build before
// this file was ever reached.
@Suite("Vision to MediaPipe landmarks")
struct LandmarkBridgeTests {
    // The one real conversion. Vision's origin is bottom left with y up,
    // MediaPipe's is top left with y down.
    @Test("y flips and x does not")
    func yFlipsAndXDoesNot() {
        let p = LandmarkBridge.toMediaPipe(x: 0.25, y: 0.10)
        #expect(abs(p.x - 0.25) < 1e-9)
        #expect(abs(p.y - 0.90) < 1e-9)
    }

    // A hand near the TOP of the camera image is y close to 1 in Vision and
    // y close to 0 in MediaPipe. Getting this backwards renders an upside
    // down hand that still looks like a hand, which is why it is asserted
    // rather than left to the eye.
    @Test("the top of the frame maps to a low y")
    func topOfFrameMapsToLowY() {
        #expect(abs(LandmarkBridge.toMediaPipe(x: 0.5, y: 0.95).y - 0.05) < 1e-9)
        #expect(abs(LandmarkBridge.toMediaPipe(x: 0.5, y: 0.05).y - 0.95) < 1e-9)
    }

    @Test("the conversion is its own inverse")
    func conversionIsItsOwnInverse() {
        for y in [0.0, 0.2, 0.5, 0.77, 1.0] {
            let once = LandmarkBridge.toMediaPipe(x: 0.3, y: y)
            let twice = LandmarkBridge.toMediaPipe(x: once.x, y: once.y)
            #expect(abs(twice.y - y) < 1e-9)
        }
    }

    // The index mapping is the identity, and this is the assertion that says
    // so. If Apple ever reorders the joint list, this fails instead of the
    // portal quietly tracking the wrong finger.
    @Test("the joint order matches MediaPipe")
    func jointOrderMatchesMediaPipe() {
        let j = HandTracker.allJoints
        #expect(j.count == 21)
        #expect(j[0] == .wrist)
        #expect(j[4] == .thumbTip)
        #expect(j[8] == .indexTip)
        #expect(j[12] == .middleTip)
        #expect(j[16] == .ringTip)
        #expect(j[20] == .littleTip)
    }

    // The portal pinches between landmark 4 and landmark 8. If those two are
    // not thumb tip and index tip, every gesture downstream is wrong.
    @Test("the pinch landmarks are the thumb and index tips")
    func pinchLandmarksAreThumbAndIndexTips() {
        #expect(HandTracker.allJoints[4] == .thumbTip)
        #expect(HandTracker.allJoints[8] == .indexTip)
    }

    @Test("the bones match OpenVision's connections")
    func bonesMatchOpenVisionConnections() {
        // OpenVision's HAND_CONNECTIONS, verbatim.
        let expected: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 4),
            (0, 5), (5, 6), (6, 7), (7, 8),
            (5, 9), (9, 10), (10, 11), (11, 12),
            (9, 13), (13, 14), (14, 15), (15, 16),
            (13, 17), (17, 18), (18, 19), (19, 20),
            (0, 17),
        ]
        let got = Set(HandTracker.bones.map { [$0.0, $0.1].sorted() }.map { "\($0[0])-\($0[1])" })
        for e in expected {
            let key = "\(min(e.0, e.1))-\(max(e.0, e.1))"
            #expect(got.contains(key), "missing bone \(key)")
        }
    }

    @Test("the json is compact and parses")
    func jsonIsCompactAndParses() throws {
        let pts = [
            LandmarkBridge.Point(x: 0.1234567, y: 0.5, z: 0),
            LandmarkBridge.Point(x: 1, y: 0, z: 0),
        ]
        let s = LandmarkBridge.json(pts)
        #expect(!s.contains(" "))
        let parsed = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [[String: Double]]
        #expect(parsed?.count == 2)
        #expect(abs((parsed?[0]["x"] ?? 0) - 0.123457) < 1e-6)
        #expect(abs(parsed?[1]["y"] ?? -1) < 1e-9)
    }

    // z is always zero because Vision's hand pose is 2D. Inventing a depth
    // would be indistinguishable from a measurement to anything downstream.
    @Test("depth is always zero")
    func depthIsAlwaysZero() {
        #expect(LandmarkBridge.toMediaPipe(x: 0.4, y: 0.6).z == 0)
    }
}
