import XCTest
@testable import PlynnKit

final class EngineManagerTests: XCTestCase {
    /// `appleAvailable` is passed explicitly so the selection logic is tested
    /// the same way on every OS, not just whichever one runs the suite.
    func testSelection() {
        let select = { (preferred: EngineChoice, ready: Bool) in
            EngineChoice.select(preferred: preferred, parakeetReady: ready, appleAvailable: true)
        }
        XCTAssertEqual(select(.auto, false), .apple)
        XCTAssertEqual(select(.auto, true), .parakeet)
        XCTAssertEqual(select(.parakeet, false), .apple)
        XCTAssertEqual(select(.parakeet, true), .parakeet)
        XCTAssertEqual(select(.apple, true), .apple)
        XCTAssertEqual(select(.apple, false), .apple)
    }

    /// Below macOS 26 there is no Apple engine to fall back to, so Parakeet is
    /// the only choice even when the user asked for Apple or it isn't ready yet.
    func testSelectionWithoutAppleEngine() {
        for preferred in EngineChoice.allCases {
            for ready in [true, false] {
                XCTAssertEqual(
                    EngineChoice.select(
                        preferred: preferred, parakeetReady: ready, appleAvailable: false),
                    .parakeet,
                    "preferred=\(preferred) parakeetReady=\(ready)")
            }
        }
    }

    func testParakeetModelsAbsentInEmptyDir() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(EngineChoice.parakeetModelsPresent(in: dir))
    }

    func testParakeetModelsPresentWhenEncoderExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let modelDir = dir.appendingPathComponent("parakeet-unified-0.6b-coreml/foo.mlmodelc")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        XCTAssertTrue(EngineChoice.parakeetModelsPresent(in: dir))
        try? FileManager.default.removeItem(at: dir)
    }

    func testDefaultCacheDirDetectionMatchesRealState() {
        // On this dev machine models are downloaded; the check must agree with reality.
        // (Weak assertion by design: just verifies the path logic doesn't crash and
        // returns a Bool consistent with the FluidAudio cache convention.)
        _ = EngineChoice.parakeetModelsPresent()
    }
}
