import Metal

/// Matches `Uniforms` in the shader: `float4` first, then the `float2`s, then
/// scalars in declaration order. Shared by the live renderer and the snapshot
/// test, so the two cannot drift apart.
struct FieldUniforms {
    var tint: SIMD4<Float>
    var pill: SIMD4<Float>
    var size: SIMD2<Float>
    var pointer: SIMD2<Float>
    var agent: SIMD2<Float>
    var parallax: SIMD2<Float>
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
    var reach: Float
    var sweep: Float
    var sweepOrigin: Float
    var embers: Float
    var pillOn: Float
}

/// The field and its glow, as five passes: the field at full size, its bright
/// parts shrunk to a quarter, a blur across, a blur down, and the composite
/// into whatever the caller is drawing to.
///
/// One type for the live view and the snapshot test, because a glow that only
/// exists on screen is a glow nobody can compare against the version before.
final class FieldPipeline {
    /// Samples of voice loudness the shader reads. Matches RIPPLE_SAMPLES.
    static let rippleSamples = 32
    /// Seconds between them. Matches RIPPLE_STEP.
    static let rippleStep = 0.05
    /// How much of the blurred rims is added back. Guessed, then judged on
    /// the snapshot: more and the band reads as fog, less and the rims stop
    /// at a hard edge again.
    static let bloomStrength: Float = 1.3

    private let field: MTLRenderPipelineState
    private let down: MTLRenderPipelineState
    private let blur: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private let device: MTLDevice
    private var fieldTexture: MTLTexture?
    private var glowA: MTLTexture?
    private var glowB: MTLTexture?

    init(device: MTLDevice, format: MTLPixelFormat) throws {
        self.device = device
        let library = try device.makeLibrary(source: presenceFieldSource, options: nil)
        func pipeline(_ fragment: String, _ format: MTLPixelFormat, blended: Bool) throws
            -> MTLRenderPipelineState
        {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "presenceVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            if blended {
                // Premultiplied over whatever is already there.
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        field = try pipeline("presenceFragment", .bgra8Unorm, blended: false)
        down = try pipeline("bloomDown", .rgba16Float, blended: false)
        blur = try pipeline("bloomBlur", .rgba16Float, blended: false)
        composite = try pipeline("bloomComposite", format, blended: true)
    }

    private func texture(_ current: MTLTexture?, _ format: MTLPixelFormat, _ width: Int, _ height: Int)
        -> MTLTexture?
    {
        if let current, current.width == width, current.height == height { return current }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func pass(_ target: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        return pass
    }

    /// Draws one frame into `output`. `voice` is the loudness history, newest
    /// first; short is padded with silence.
    func encode(
        _ buffer: MTLCommandBuffer, into output: MTLRenderPassDescriptor,
        width: Int, height: Int, uniforms: inout FieldUniforms, voice: [Float]
    ) {
        let quarterWidth = max(width / 4, 1), quarterHeight = max(height / 4, 1)
        fieldTexture = texture(fieldTexture, .bgra8Unorm, width, height)
        glowA = texture(glowA, .rgba16Float, quarterWidth, quarterHeight)
        glowB = texture(glowB, .rgba16Float, quarterWidth, quarterHeight)
        guard let fieldTexture, let glowA, let glowB else { return }

        var samples = Array(voice.prefix(Self.rippleSamples))
        samples += Array(repeating: 0, count: Self.rippleSamples - samples.count)

        func run(_ descriptor: MTLRenderPassDescriptor, _ state: MTLRenderPipelineState,
                 _ body: (MTLRenderCommandEncoder) -> Void)
        {
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            encoder.setRenderPipelineState(state)
            body(encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        run(pass(fieldTexture), field) { encoder in
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FieldUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&samples, length: MemoryLayout<Float>.stride * samples.count, index: 1)
        }
        run(pass(glowA), down) { $0.setFragmentTexture(fieldTexture, index: 0) }
        var across = SIMD2<Float>(1, 0), downward = SIMD2<Float>(0, 1)
        run(pass(glowB), blur) { encoder in
            encoder.setFragmentTexture(glowA, index: 0)
            encoder.setFragmentBytes(&across, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        }
        run(pass(glowA), blur) { encoder in
            encoder.setFragmentTexture(glowB, index: 0)
            encoder.setFragmentBytes(&downward, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        }
        var strength = Self.bloomStrength
        run(output, composite) { encoder in
            encoder.setFragmentTexture(fieldTexture, index: 0)
            encoder.setFragmentTexture(glowA, index: 1)
            encoder.setFragmentBytes(&strength, length: MemoryLayout<Float>.stride, index: 0)
        }
    }
}
