import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
// ScreenCaptureKit predates Sendable: its content and screenshot types are
// plain classes the compiler cannot vouch for, and they never leave this
// actor here.
@preconcurrency import ScreenCaptureKit

/// What is on the screen behind the pill, so the glass can bend it and the
/// ink can pick a colour against it.
///
/// This is the permission `SurfaceChrome.bare` declined in its comments: "a
/// real heads-up display measures the luminance behind itself and flips its
/// ink".
/// On 2026-09-22 the ask became refraction and adaptive ink, both of which
/// are that measurement, so it is taken here, once, for the pill's rectangle
/// only and never for the whole display.
///
/// Without Screen Recording nothing here runs and the pill is exactly the
/// clear glass it was: white ink with its own shadow, no lens.
@MainActor
@Observable
public final class BackdropSampler {
    public static let shared = BackdropSampler()

    /// The screen behind the pill, bent through a lens the pill's shape.
    public private(set) var lens: CGImage?
    /// Mean luminance behind the pill, 0 to 1. Nil until a sample lands.
    public private(set) var luminance: Double?

    /// Above this the ink turns dark. 0.62 is the light ground the snapshot
    /// tests use (0.97) pulled down past a grey desktop picture (about 0.5),
    /// so a mid-grey keeps white ink. Guessed, never measured on a real one.
    public static let lightGround = 0.62
    /// Frames a second while the pill is up. Twelve keeps a scrolling page
    /// from smearing for more than a frame at reading speed; more is heat for
    /// a 440 point strip. Guessed, never measured.
    static let rate: Double = 12
    /// Captured past the pill's own edge, so the lens has something to pull
    /// in from outside the capsule the way a real lens does.
    static let bleed: CGFloat = 10
    static let askedKey = "hud.backdrop.asked"

    @ObservationIgnored private let context = CIContext(options: [.cacheIntermediates: false])

    /// Keep sampling the rectangle `frame` returns, in overlay points with a
    /// top-left origin, for as long as the calling task lives.
    public func follow(_ frame: @escaping @MainActor () -> CGRect?) async {
        guard CGPreflightScreenCaptureAccess() else {
            // Ask once, ever. The system dialogue is the only way to the
            // switch, and a HUD that asks on every launch gets quit.
            if !UserDefaults.standard.bool(forKey: Self.askedKey) {
                UserDefaults.standard.set(true, forKey: Self.askedKey)
                _ = CGRequestScreenCaptureAccess()
            }
            return
        }
        guard let filter = await Self.filter() else { return }
        while !Task.isCancelled {
            if let rect = frame() {
                await sample(rect, filter: filter)
            } else if lens != nil {
                lens = nil
                luminance = nil
            }
            try? await Task.sleep(for: .seconds(1 / Self.rate))
        }
    }

    /// The main display with this app left out, so the glass never samples
    /// itself and folds into a hall of mirrors.
    private static func filter() async -> SCContentFilter? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true),
              let screen = OverlayWindow.active,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == number })
        else { return nil }
        let own = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
    }

    private func sample(_ rect: CGRect, filter: SCContentFilter) async {
        let region = rect.insetBy(dx: -Self.bleed, dy: -Self.bleed)
        let config = SCStreamConfiguration()
        config.sourceRect = region
        let scale = OverlayWindow.active?.backingScaleFactor ?? 2
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.showsCursor = false
        guard let shot = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
        else { return }
        let image = CIImage(cgImage: shot)
        luminance = average(image)
        lens = bend(image, pill: rect.size, scale: scale)
    }

    /// A lozenge lens along the capsule's spine: the classic glass rod. The
    /// refraction of 1.4 bends the edges visibly and leaves the centre
    /// readable, which is where the text sits. Guessed, never measured.
    private func bend(_ image: CIImage, pill: CGSize, scale: CGFloat) -> CGImage? {
        let lens = CIFilter.glassLozenge()
        lens.inputImage = image
        let midY = image.extent.midY
        let radius = pill.height * scale / 2
        let inset = Self.bleed * scale + radius
        lens.point0 = CGPoint(x: image.extent.minX + inset, y: midY)
        lens.point1 = CGPoint(x: image.extent.maxX - inset, y: midY)
        lens.radius = Float(radius)
        lens.refraction = 1.4
        guard let bent = lens.outputImage?.cropped(to: image.extent) else { return nil }
        return context.createCGImage(bent, from: image.extent)
    }

    private func average(_ image: CIImage) -> Double? {
        let mean = CIFilter.areaAverage()
        mean.inputImage = image
        mean.extent = image.extent
        guard let output = mean.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: output.extent,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // Rec. 709 weights: what the eye calls bright, not what the
        // channels add up to.
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }
}
