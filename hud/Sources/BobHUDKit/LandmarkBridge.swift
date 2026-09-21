import Foundation
import Vision

/// Turns an Apple Vision hand observation into the 21 landmarks the web
/// portal expects.
///
/// WHY THIS IS NOT MEDIAPIPE. The obvious way to put a hand-tracked portal on
/// the HUD is to load the browser build into a WKWebView and let MediaPipe
/// use the camera. It works, and it is wrong here: it opens a SECOND camera
/// stream next to the one the HUD already runs, pulls a WASM model off a CDN
/// on every launch, and costs several times the CPU. Apple Vision is already
/// in this process and measured at 7.56ms for one hand, 4-6% of one core
/// sustained on an M4 Pro. So Vision produces the landmarks and the web layer
/// only draws.
///
/// WHAT ACTUALLY NEEDS CONVERTING. Very little, which is worth stating
/// because the plan budgeted a day for it:
///
///   * ORDER. Vision's joints, listed wrist, thumb, index, middle, ring,
///     little, already land in MediaPipe's 0-20 order. The mapping is the
///     identity. `HandTracker.allJoints` is that list and `bones` already
///     matches OpenVision's `HAND_CONNECTIONS`.
///   * ORIGIN. This is the whole conversion. Vision normalizes with the
///     origin at the BOTTOM left and y increasing upward. MediaPipe puts the
///     origin at the TOP left with y increasing downward. So y flips and x
///     does not.
///   * DEPTH. Vision's hand pose is 2D. There is no z, and inventing one
///     would be a lie that a caller could not distinguish from a measurement,
///     so z is always 0 and the web side must not depend on it.
///
/// Getting the flip wrong produces a hand that is upside down but plausible,
/// which is the worst kind of bug to find by waving at a laptop, so the
/// conversion is a pure function with tests rather than two characters buried
/// in a render loop.
public enum LandmarkBridge {
    /// One landmark, in MediaPipe's convention.
    public struct Point: Sendable, Equatable, Codable {
        public let x: Double
        public let y: Double
        public let z: Double

        public init(x: Double, y: Double, z: Double = 0) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// Vision normalized coordinates to MediaPipe normalized coordinates.
    ///
    /// Origin moves from the bottom left to the top left, so y flips and x is
    /// unchanged. Pure, so it can be tested without a camera.
    public static func toMediaPipe(x: Double, y: Double) -> Point {
        Point(x: x, y: 1 - y, z: 0)
    }

    /// Below this, Vision is guessing. A low-confidence joint reported as
    /// fact makes a finger snap across the frame, and one bad landmark is
    /// enough to throw the circle fit off, so the whole hand is dropped
    /// rather than partially trusted.
    public static let minConfidence: Float = 0.3

    /// All 21 landmarks, or nil if any joint is missing or unconfident.
    ///
    /// All or nothing on purpose. A partial hand is worse than no hand here:
    /// the gesture layer downstream measures angles between fingertips, and a
    /// silently substituted joint produces a confident wrong answer.
    public static func landmarks(
        from observation: VNHumanHandPoseObservation,
        minConfidence: Float = LandmarkBridge.minConfidence
    ) -> [Point]? {
        var out: [Point] = []
        out.reserveCapacity(HandTracker.allJoints.count)
        for joint in HandTracker.allJoints {
            guard let p = try? observation.recognizedPoint(joint),
                  p.confidence >= minConfidence
            else { return nil }
            out.append(toMediaPipe(x: Double(p.location.x), y: Double(p.location.y)))
        }
        return out.count == 21 ? out : nil
    }

    /// The landmarks as the JSON array the web layer is fed.
    ///
    /// Hand-rolled rather than JSONEncoder: this runs up to 30 times a second
    /// and the shape is three numbers. Six decimal places is about a
    /// thousandth of a pixel at any sane resolution and keeps the string
    /// short, because the cost here is the string crossing into JavaScript.
    public static func json(_ points: [Point]) -> String {
        var s = "["
        for (i, p) in points.enumerated() {
            if i > 0 { s += "," }
            s += "{\"x\":\(round(p.x * 1e6) / 1e6),\"y\":\(round(p.y * 1e6) / 1e6),\"z\":0}"
        }
        return s + "]"
    }
}
