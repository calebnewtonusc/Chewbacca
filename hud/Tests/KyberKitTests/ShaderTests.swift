import Metal
import Testing

@testable import KyberKit

/// Compile the presence field's Metal, on a real device, in CI.
///
/// The shader is a string compiled at launch, which is what keeps a full Xcode
/// install out of the build requirements. The cost of that trade is that
/// nothing about `swift build` can tell you the shader is broken: a syntax
/// error in here compiles, ships, logs one line at runtime, and leaves the
/// person with no field at all and no idea why. That happened often enough
/// while the shader was being reworked to be worth a test.
@Suite("Shader")
struct ShaderTests {
    @Test("the presence field compiles")
    func presenceCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No GPU, which is a machine this package cannot draw on at all.
            // Failing here would report a missing device as a broken shader.
            return
        }
        let library = try device.makeLibrary(source: presenceFieldSource, options: nil)
        #expect(library.makeFunction(name: "presenceVertex") != nil)
        #expect(library.makeFunction(name: "presenceFragment") != nil)
    }
}
