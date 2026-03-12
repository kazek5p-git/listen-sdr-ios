import XCTest
@testable import ListenSDR

final class AudioPCMUtilitiesTests: XCTestCase {
  func testResampleMonoReturnsOriginalSamplesWhenRateMatches() {
    let input: [Float] = [0, 0.25, -0.5, 1.0]

    let output = AudioPCMUtilities.resampleMono(input, from: 48_000, to: 48_000)

    XCTAssertEqual(output, input)
  }

  func testResampleMonoUpsamplesToExpectedLength() {
    let input: [Float] = [0, 1, 0, -1]

    let output = AudioPCMUtilities.resampleMono(input, from: 12_000, to: 48_000)

    XCTAssertEqual(output.count, 16)
    XCTAssertEqual(Double(output.first ?? .zero), 0, accuracy: 0.0001)
    XCTAssertEqual(Double(output.last ?? .zero), -1, accuracy: 0.0001)
  }

  func testSanitizedInputSampleRateFallsBackForInvalidRate() {
    XCTAssertEqual(AudioPCMUtilities.sanitizedInputSampleRate(0), AudioPCMUtilities.preferredOutputSampleRate)
    XCTAssertEqual(AudioPCMUtilities.sanitizedInputSampleRate(.nan), AudioPCMUtilities.preferredOutputSampleRate)
  }
}
