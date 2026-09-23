import AppKit
import AVFoundation
import Observation
import SwiftUI
import Vision

/// Doctor Strange overlay: draws the hand skeleton on a transparent window.
///
/// This is a demo. The production gestures live in HandTracker inside
/// KyberKit and go through onGesture; this target exists so the skeleton
/// is visible on camera for a demo recording.
///
/// Run: swift run HandDemo
/// Quit: Cmd-Q or close the window.
@MainActor
@Observable
final class SkeletonModel {
    var skeletons: [[CGPoint]] = []
}

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private var session: AVCaptureSession?
    private let delegateQueue = DispatchQueue(label: "hand.demo", qos: .userInteractive)
    private var handler: DemoSessionHandler?
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    let skeletonModel = SkeletonModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let view = SkeletonCanvas(model: skeletonModel)
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        window = panel

        startCamera()
    }

    private func startCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        nonisolated(unsafe) let req = self.request
        let handler = DemoSessionHandler { [weak self] buffer in
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
            let imageHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? imageHandler.perform([req])
            let results = req.results ?? []
            var allSkeletons: [[CGPoint]] = []
            for obs in results {
                var points: [CGPoint] = []
                for joint in allJoints {
                    if let p = try? obs.recognizedPoint(joint), p.confidence > 0.1 {
                        points.append(CGPoint(x: Double(p.x), y: Double(p.y)))
                    } else {
                        points.append(CGPoint(x: -1, y: -1))
                    }
                }
                allSkeletons.append(points)
            }
            Task { @MainActor in
                self?.skeletonModel.skeletons = allSkeletons
            }
        }
        output.setSampleBufferDelegate(handler, queue: delegateQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        self.session = session
        self.handler = handler
        delegateQueue.async { session.startRunning() }
    }
}

/// The 21 joints in order.
private let allJoints: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip,
]

/// Bone connections.
private let bones: [(Int, Int)] = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (0, 9), (9, 10), (10, 11), (11, 12),
    (0, 13), (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
    (5, 9), (9, 13), (13, 17),
]

/// Per-bone colour for the Doctor Strange look.
private func boneColor(_ index: Int) -> Color {
    switch index {
    case 0...3: return .orange   // thumb
    case 4...7: return .cyan     // index
    case 8...11: return .green   // middle
    case 12...15: return .purple // ring
    case 16...19: return .pink   // little
    default: return .yellow      // palm
    }
}

struct SkeletonCanvas: View {
    let model: SkeletonModel

    var body: some View {
        Canvas { context, size in
            for skeleton in model.skeletons {
                drawSkeleton(skeleton, in: context, size: size)
            }
        }
        .ignoresSafeArea()
    }

    private func drawSkeleton(
        _ points: [CGPoint], in context: GraphicsContext, size: CGSize
    ) {
        for (boneIndex, bone) in bones.enumerated() {
            let a = points[bone.0]
            let b = points[bone.1]
            guard a.x >= 0, b.x >= 0 else { continue }
            // Mirror x for front camera, flip y for screen coords.
            let screenA = CGPoint(
                x: (1.0 - a.x) * size.width,
                y: (1.0 - a.y) * size.height)
            let screenB = CGPoint(
                x: (1.0 - b.x) * size.width,
                y: (1.0 - b.y) * size.height)
            var path = Path()
            path.move(to: screenA)
            path.addLine(to: screenB)
            let color = boneColor(boneIndex)
            // Glow: a wide translucent stroke behind the main one.
            context.stroke(path, with: .color(color.opacity(0.3)), lineWidth: 8)
            context.stroke(path, with: .color(color), lineWidth: 2.5)
        }

        for (i, point) in points.enumerated() {
            guard point.x >= 0 else { continue }
            let screen = CGPoint(
                x: (1.0 - point.x) * size.width,
                y: (1.0 - point.y) * size.height)
            let radius: CGFloat = i == 0 ? 6 : 4
            let rect = CGRect(
                x: screen.x - radius, y: screen.y - radius,
                width: radius * 2, height: radius * 2)
            let isTip = [4, 8, 12, 16, 20].contains(i)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(isTip ? .white : .white.opacity(0.7)))
            if isTip {
                let glowRect = rect.insetBy(dx: -4, dy: -4)
                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .color(.cyan.opacity(0.25)))
            }
        }
    }
}

private final class DemoSessionHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
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

let app = NSApplication.shared
let delegate = DemoDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
