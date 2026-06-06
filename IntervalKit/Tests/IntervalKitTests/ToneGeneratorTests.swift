import XCTest
@testable import IntervalKit

final class ToneGeneratorTests: XCTestCase {
    func test_sineWaveSamples_producesExpectedFrameCount() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 880, duration: 0.2, sampleRate: 44_100)

        XCTAssertEqual(samples.count, 8_820)
    }

    func test_sineWaveSamples_staysWithinAmplitudeBounds() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0.5, amplitude: 0.6)

        XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.6 + 0.0001 })
        XCTAssertTrue(samples.contains { abs($0) > 0.1 })
    }

    func test_sineWaveSamples_fadesInAndOutToAvoidClicks() throws {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0.5, amplitude: 0.6)

        let first = try XCTUnwrap(samples.first)
        let last = try XCTUnwrap(samples.last)
        XCTAssertEqual(first, 0, accuracy: 0.001)
        XCTAssertEqual(last, 0, accuracy: 0.05)
    }

    func test_zeroDuration_producesNoSamples() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0)

        XCTAssertTrue(samples.isEmpty)
    }
}
