import XCTest
import Vision
@testable import BobHUDKit

final class LandmarkBridgeTests: XCTestCase {
    // The one real conversion. Vision's origin is bottom left with y up,
    // MediaPipe's is top left with y down.
    func testYFlipsAndXDoesNot() {
        let p = LandmarkBridge.toMediaPipe(x: 0.25, y: 0.10)
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.90, accuracy: 1e-9)
    }

    // A hand near the TOP of the camera image is y close to 1 in Vision and
    // y close to 0 in MediaPipe. Getting this backwards renders an upside
    // down hand that still looks like a hand, which is why it is asserted
    // rather than left to the eye.
    func testTopOfFrameMapsToLowY() {
        XCTAssertEqual(LandmarkBridge.toMediaPipe(x: 0.5, y: 0.95).y, 0.05, accuracy: 1e-9)
        XCTAssertEqual(LandmarkBridge.toMediaPipe(x: 0.5, y: 0.05).y, 0.95, accuracy: 1e-9)
    }

    func testConversionIsItsOwnInverse() {
        for y in [0.0, 0.2, 0.5, 0.77, 1.0] {
            let once = LandmarkBridge.toMediaPipe(x: 0.3, y: y)
            let twice = LandmarkBridge.toMediaPipe(x: once.x, y: once.y)
            XCTAssertEqual(twice.y, y, accuracy: 1e-9)
        }
    }

    // The index mapping is the identity, and this is the assertion that says
    // so. If Apple ever reorders the joint list, this fails instead of the
    // portal quietly tracking the wrong finger.
    func testJointOrderMatchesMediaPipe() {
        let j = HandTracker.allJoints
        XCTAssertEqual(j.count, 21)
        XCTAssertEqual(j[0], .wrist)
        XCTAssertEqual(j[4], .thumbTip)
        XCTAssertEqual(j[8], .indexTip)
        XCTAssertEqual(j[12], .middleTip)
        XCTAssertEqual(j[16], .ringTip)
        XCTAssertEqual(j[20], .littleTip)
    }

    // The portal pinches between landmark 4 and landmark 8. If those two are
    // not thumb tip and index tip, every gesture downstream is wrong.
    func testPinchLandmarksAreThumbAndIndexTips() {
        XCTAssertEqual(HandTracker.allJoints[4], .thumbTip)
        XCTAssertEqual(HandTracker.allJoints[8], .indexTip)
    }

    func testBonesMatchOpenVisionConnections() {
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
            XCTAssertTrue(got.contains(key), "missing bone \(key)")
        }
    }

    func testJsonIsCompactAndParses() throws {
        let pts = [
            LandmarkBridge.Point(x: 0.1234567, y: 0.5, z: 0),
            LandmarkBridge.Point(x: 1, y: 0, z: 0),
        ]
        let s = LandmarkBridge.json(pts)
        XCTAssertFalse(s.contains(" "))
        let parsed = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [[String: Double]]
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[0]["x"] ?? 0, 0.123457, accuracy: 1e-6)
        XCTAssertEqual(parsed?[1]["y"] ?? -1, 0, accuracy: 1e-9)
    }

    // z is always zero because Vision's hand pose is 2D. Inventing a depth
    // would be indistinguishable from a measurement to anything downstream.
    func testDepthIsAlwaysZero() {
        XCTAssertEqual(LandmarkBridge.toMediaPipe(x: 0.4, y: 0.6).z, 0)
    }
}
