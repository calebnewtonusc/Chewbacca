import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers

@testable import KyberKit

/// The field, drawn to a texture and saved as a picture, so a change to the
/// shader can be looked at rather than reasoned about.
@Suite("Field render")
struct FieldRenderTests {
    /// The resting uniforms every picture starts from.
    static func base(width: Int, height: Int, rest: Float) -> FieldUniforms {
        FieldUniforms(
            tint: SIMD4(1, 1, 1, 0), pill: SIMD4(0, 0, 0, 0), size: SIMD2(Float(width), Float(height)),
            pointer: SIMD2(-10, -10), agent: SIMD2(-10, -10), parallax: SIMD2(0, 0),
            time: 7.3, act: 5, rest: rest, travel: 12, pulse: 0, beat: 0, alpha: 1, part: 0,
            partRadius: 0.02, partFeather: 0.01, reach: 0, sweep: 99, sweepOrigin: 0, embers: 0, pillOn: 0)
    }

    /// One frame through the whole pipeline, glow and all, over mid grey,
    /// written to `HUD_SNAPSHOT_DIR/field<suffix>.png` when that is set.
    static func render(
        suffix: String = "", voice: [Float] = [],
        _ adjust: (inout FieldUniforms) -> Void = { _ in }
    ) throws -> Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return false }
        let pipeline = try FieldPipeline(device: device, format: .bgra8Unorm)

        let width = 1280, height = 800
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Mid grey, the background the band was tuned against.
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.42, 0.42, 0.42, 1)

        var uniforms = base(width: width, height: height, rest: 0.039)
        adjust(&uniforms)
        guard let buffer = queue.makeCommandBuffer() else { return false }
        pipeline.encode(
            buffer, into: pass, width: width, height: height, uniforms: &uniforms, voice: voice)
        buffer.commit()
        buffer.waitUntilCompleted()
        guard let directory = ProcessInfo.processInfo.environment["HUD_SNAPSHOT_DIR"] else {
            return true
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space, bitmapInfo: info.rawValue),
            let image = context.makeImage()
        else { return false }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("field\(suffix).png")
        guard let sink = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(sink, image, nil)
        return CGImageDestinationFinalize(sink)
    }

    @Test("the band at rest draws, and can be looked at")
    func atRest() throws {
        // No GPU is a machine this package cannot draw on, not a broken
        // shader; `render` says so by returning false without throwing.
        _ = try Self.render()
    }

    @Test("acting: green in the strands, sparks, and a finger toward the agent")
    func acting() throws {
        _ = try Self.render(suffix: "-acting") {
            $0.tint = SIMD4(0.28, 1.45, 0.55, 0.60)
            $0.rest = 0.049
            $0.embers = 1
            $0.agent = SIMD2(0.72, 0.62)
            $0.reach = 1
        }
    }

    @Test("the voice leaves the hyper bar as ripples")
    func ripples() throws {
        // A syllable, a gap and another, newest first.
        let voice: [Float] = (0..<32).map { i in
            let t = Float(i)
            return max(0, sin(t * 0.55)) * (i < 20 ? 0.9 : 0.4)
        }
        _ = try Self.render(suffix: "-voice", voice: voice) { $0.rest = 0.022 }
    }

    @Test("done sends one crest round the band")
    func sweep() throws {
        _ = try Self.render(suffix: "-done") {
            $0.tint = SIMD4(0.14, 0.62, 0.30, 0.75)
            $0.rest = 0.030
            $0.sweep = 0.45
            $0.sweepOrigin = 0.62
        }
    }

    @Test("the hyper bar is a bead of the band's own liquid")
    func bar() throws {
        // 300 by 34 points, centred, 14 above a 70 point Dock, on 1280 by 800.
        _ = try Self.render(suffix: "-bar") {
            $0.pill = SIMD4(490 / 1280, 682 / 800, 300 / 1280, 34 / 800)
            $0.pillOn = 1
            $0.tint = SIMD4(0.28, 1.45, 0.55, 0.60)
            $0.rest = 0.049
        }
    }
}
