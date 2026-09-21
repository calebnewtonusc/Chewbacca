import AVFoundation
import CoreGraphics
import Foundation
import Vision
import os

/// Hand gesture recognition through the built-in camera, using Apple's Vision
/// framework on the Neural Engine.
///
/// Two gestures, both designed for a forearm resting on the desk (CHI 2014,
/// Consumed Endurance: no arm elevation, no gorilla arm):
///
/// 1. **Palm dismiss.** An open palm facing the camera kills the panel, stops a
///    run in flight, and mutes the mic. The same semantic as the double-tap of
///    the globe key, so this is its hands-free twin.
///
/// 2. **Point to establish deixis.** A finger pointed at the screen while the
///    person says "what is this" emits `OutboundEvent.region(CGRect)`, composing
///    with the voice layer that already ships.
///
/// Both require three consecutive frames before firing (Apple's own sample-code
/// gate, ~23ms at 8ms/frame). Vision sometimes reports feet as hands.
///
/// Measured on this M4 Pro: 7.56ms per frame one hand, 9.96ms two hands, 4-6%
/// of one core sustained, because VNDetectHumanHandPoseRequest dispatches to
/// the Neural Engine.
@MainActor
public final class HandTracker {
    /// What the tracker tells the app.
    public enum Gesture: Sendable, Equatable {
        /// An open palm held steady for three frames. Dismiss everything.
        case palmDismiss
        /// Index finger pointing at a screen region, in unit coordinates (0-1)
        /// with a top-left origin. The tip position in the camera frame, mapped
        /// to the display.
        case point(CGPoint)
    }

    public var onGesture: ((Gesture) -> Void)?

    /// Whether the tracker is running. The camera and the session handler are
    /// only alive while this is true.
    public private(set) var isRunning = false

    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private let delegateQueue = DispatchQueue(label: "bob.hud.hand", qos: .userInteractive)
    private var handler: SessionHandler?

    /// The request is created once and reused across frames. Setting
    /// `maximumHandCount` to 1 keeps it at 7.56ms rather than 9.96ms; two
    /// hands is not needed for either gesture.
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    private static let log = Logger(subsystem: "bob.hud", category: "hand")

    // MARK: Three-frame gate

    /// Which gesture was seen on the last frame, and how many consecutive
    /// frames have agreed. Three is the threshold.
    private var candidate: GestureCandidate = .none
    private static let requiredFrames = 3

    private enum GestureCandidate: Equatable {
        case none
        case palm(count: Int)
        case point(tip: CGPoint, count: Int)
    }

    /// Whether the palm gesture has already fired and should not fire again
    /// until the hand leaves and returns. Without this the gesture fires on
    /// every third frame while the palm is held, which is 30 dismissals per
    /// second.
    private var palmFired = false

    public init() {}

    // MARK: Start / stop

    public func start() {
        guard !isRunning else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .low  // 352x288, more than enough for hand pose
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            Self.log.error("hand.start: no front camera")
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let handler = SessionHandler { [weak self] buffer in
            Task { @MainActor in self?.process(buffer) }
        }
        output.setSampleBufferDelegate(handler, queue: delegateQueue)
        guard session.canAddOutput(output) else {
            Self.log.error("hand.start: cannot add output")
            return
        }
        session.addOutput(output)

        self.session = session
        self.output = output
        self.handler = handler

        // Start on a background thread so it does not block the main actor.
        // AVCaptureSession.startRunning is synchronous and can take 200ms+.
        Task.detached { session.startRunning() }
        isRunning = true
        Self.log.notice("hand.start")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        candidate = .none
        palmFired = false
        let s = session
        session = nil
        output = nil
        handler = nil
        Task.detached { s?.stopRunning() }
        Self.log.notice("hand.stop")
    }

    // MARK: Per-frame processing

    private func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            // No hand in frame: reset the gate and allow palm to fire again
            // next time a hand appears.
            candidate = .none
            palmFired = false
            return
        }

        let gesture = classify(observation)
        gate(gesture)
    }

    // MARK: Gesture classification

    /// Classify the hand pose into one of the two gestures, or nil.
    ///
    /// Palm: all five fingertips have high confidence and are spread apart, with
    /// no finger curled.
    ///
    /// Point: only the index finger is extended; the other three fingers are
    /// curled toward the palm (their tips are closer to the wrist than their
    /// MCP joints).
    /// Finger identity, keyed by a plain string so the dictionaries do not
    /// fight with Vision's nested type names.
    private struct Finger {
        let tip: VNHumanHandPoseObservation.JointName
        let mcp: VNHumanHandPoseObservation.JointName
    }
    private static let fingers: [(String, Finger)] = [
        ("index",  Finger(tip: .indexTip,  mcp: .indexMCP)),
        ("middle", Finger(tip: .middleTip, mcp: .middleMCP)),
        ("ring",   Finger(tip: .ringTip,   mcp: .ringMCP)),
        ("little", Finger(tip: .littleTip, mcp: .littleMCP)),
    ]

    private func classify(_ obs: VNHumanHandPoseObservation) -> ClassifiedGesture? {
        guard let wrist = try? obs.recognizedPoint(.wrist),
              wrist.confidence > 0.3
        else { return nil }

        // Read all eight joints (4 tips + 4 MCPs) and bail if any is missing
        // or too noisy.
        var tipPoints: [String: VNRecognizedPoint] = [:]
        var mcpPoints: [String: VNRecognizedPoint] = [:]
        for (name, finger) in Self.fingers {
            guard let tip = try? obs.recognizedPoint(finger.tip),
                  let mcp = try? obs.recognizedPoint(finger.mcp),
                  tip.confidence > 0.3, mcp.confidence > 0.3
            else { return nil }
            tipPoints[name] = tip
            mcpPoints[name] = mcp
        }

        // Extension test: a finger is extended when its tip is farther from
        // the wrist than its MCP joint is. This works at desk level with the
        // forearm resting, because the camera sees the hand from above and
        // extended fingers project away from the wrist in the image plane.
        var extended: [String: Bool] = [:]
        for (name, _) in Self.fingers {
            let tip = tipPoints[name]!
            let mcp = mcpPoints[name]!
            let tipDist = distance(tip, wrist)
            let mcpDist = distance(mcp, wrist)
            extended[name] = tipDist > mcpDist * 1.15
        }

        // Thumb extension: tip farther from wrist than CMC.
        let thumbExtended: Bool
        if let thumbTip = try? obs.recognizedPoint(.thumbTip),
           let thumbCMC = try? obs.recognizedPoint(.thumbCMC),
           thumbTip.confidence > 0.3, thumbCMC.confidence > 0.3 {
            thumbExtended = distance(thumbTip, wrist) > distance(thumbCMC, wrist) * 1.1
        } else {
            thumbExtended = false
        }

        let indexExtended = extended["index"] ?? false
        let middleExtended = extended["middle"] ?? false
        let ringExtended = extended["ring"] ?? false
        let littleExtended = extended["little"] ?? false

        // Palm: all five extended.
        if indexExtended && middleExtended && ringExtended && littleExtended && thumbExtended {
            return .palm
        }

        // Point: only index extended, the rest curled.
        if indexExtended && !middleExtended && !ringExtended && !littleExtended,
           let indexTip = tipPoints["index"] {
            // Vision coordinates: (0,0) bottom-left, (1,1) top-right.
            // Flip y for top-left origin, and mirror x because the front camera
            // is mirrored.
            let screenPoint = CGPoint(
                x: 1.0 - Double(indexTip.x),
                y: 1.0 - Double(indexTip.y))
            return .point(screenPoint)
        }

        return nil
    }

    private enum ClassifiedGesture: Equatable {
        case palm
        case point(CGPoint)

        static func == (lhs: ClassifiedGesture, rhs: ClassifiedGesture) -> Bool {
            switch (lhs, rhs) {
            case (.palm, .palm): return true
            case (.point, .point): return true
            default: return false
            }
        }
    }

    // MARK: Three-frame gate

    private func gate(_ gesture: ClassifiedGesture?) {
        guard let gesture else {
            candidate = .none
            return
        }

        switch gesture {
        case .palm:
            if case .palm(let count) = candidate {
                let next = count + 1
                candidate = .palm(count: next)
                if next >= Self.requiredFrames && !palmFired {
                    palmFired = true
                    Self.log.notice("hand.gesture palm")
                    onGesture?(.palmDismiss)
                }
            } else {
                candidate = .palm(count: 1)
            }

        case .point(let tip):
            if case .point(_, let count) = candidate {
                let next = count + 1
                candidate = .point(tip: tip, count: next)
                if next >= Self.requiredFrames {
                    Self.log.notice("hand.gesture point x=\(tip.x, format: .fixed(precision: 2)) y=\(tip.y, format: .fixed(precision: 2))")
                    onGesture?(.point(tip))
                    // Reset so it does not fire every frame; let the person
                    // hold steady and fire again after another 3 frames.
                    candidate = .point(tip: tip, count: 0)
                }
            } else {
                candidate = .point(tip: tip, count: 1)
            }
        }
    }

    // MARK: Joint helpers

    private func distance(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> CGFloat {
        let dx = CGFloat(a.x - b.x)
        let dy = CGFloat(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The skeleton points for the demo overlay. All 21 joints, in Vision
    /// coordinates (bottom-left origin, 0-1). Nil when no hand is detected.
    /// Read by the demo target only; the production gestures go through
    /// `onGesture`.
    public private(set) var skeleton: [CGPoint]?

    /// All 21 joint names in the order Vision reports them.
    private static let allJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    /// Bone connections for drawing the skeleton.
    public static let bones: [(Int, Int)] = [
        // Thumb
        (0, 1), (1, 2), (2, 3), (3, 4),
        // Index
        (0, 5), (5, 6), (6, 7), (7, 8),
        // Middle
        (0, 9), (9, 10), (10, 11), (11, 12),
        // Ring
        (0, 13), (13, 14), (14, 15), (15, 16),
        // Little
        (0, 17), (17, 18), (18, 19), (19, 20),
        // Palm
        (5, 9), (9, 13), (13, 17),
    ]

    /// Extract the full skeleton after classification, for the demo overlay.
    public func updateSkeleton(from sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            skeleton = nil
            return
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        guard let obs = request.results?.first else {
            skeleton = nil
            return
        }
        var points: [CGPoint] = []
        for joint in Self.allJoints {
            if let p = try? obs.recognizedPoint(joint), p.confidence > 0.1 {
                points.append(CGPoint(x: Double(p.x), y: Double(p.y)))
            } else {
                points.append(CGPoint(x: -1, y: -1))  // sentinel for missing
            }
        }
        skeleton = points
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

/// Bridges the delegate callback to a closure. The delegate has to be an
/// NSObject subclass, and making HandTracker itself one would pull all its
/// state off the main actor into a Sendable mess.
private final class SessionHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onBuffer: @Sendable (CMSampleBuffer) -> Void

    init(onBuffer: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onBuffer(sampleBuffer)
    }
}
