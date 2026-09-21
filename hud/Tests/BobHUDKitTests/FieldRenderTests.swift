import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers

@testable import BobHUDKit

/// The field, drawn to a texture and saved as a picture, so a change to the
/// shader can be looked at rather than reasoned about.
@Suite("Field render")
struct FieldRenderTests {
    /// Matches `Uniforms` in the shader: `float4` first, then two `float2`,
    /// then scalars in declaration order.
    struct Uniforms {
        var tint: SIMD4<Float>
        var size: SIMD2<Float>
        var pointer: SIMD2<Float>
        var time: Float
        var act: Float
        var rest: Float
        var travel: Float
        var pulse: Float
        var beat: Float
        var alpha: Float
        var part: Float
        var partRadius: Float
        var partFeather: Float
    }

    /// One frame of the band at rest, over mid grey, written to
    /// `HUD_SNAPSHOT_DIR/field<suffix>.png` when that directory is set.
    static func render(source: String, rest: Float, suffix: String = "") throws -> Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return false }
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "presenceVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "presenceFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

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

        var uniforms = Uniforms(
            tint: SIMD4(1, 1, 1, 0), size: SIMD2(Float(width), Float(height)),
            pointer: SIMD2(-10, -10), time: 7.3, act: 5, rest: rest, travel: 12, pulse: 0,
            beat: 0, alpha: 1, part: 0, partRadius: 0.02, partFeather: 0.01)
        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
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
        _ = try Self.render(source: presenceFieldSource, rest: 0.039)
    }
}
