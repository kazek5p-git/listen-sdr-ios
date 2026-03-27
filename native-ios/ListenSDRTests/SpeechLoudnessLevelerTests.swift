import XCTest
@testable import ListenSDR

final class SpeechLoudnessLevelerTests: XCTestCase {
  func testBoostsQuietSpeechWithoutClipping() {
    let leveler = SpeechLoudnessLeveler()
    var processed: [Float] = []

    for _ in 0..<10 {
      processed = leveler.process(Array(repeating: Float(0.02), count: 2_048))
    }

    XCTAssertGreaterThan(rms(processed), 0.02)
    XCTAssertLessThanOrEqual(peak(processed), 0.92)
  }

  func testReducesVeryLoudSpeech() {
    let leveler = SpeechLoudnessLeveler()
    var processed: [Float] = []

    for _ in 0..<6 {
      processed = leveler.process(Array(repeating: Float(0.80), count: 2_048))
    }

    XCTAssertLessThan(rms(processed), 0.80)
    XCTAssertLessThanOrEqual(peak(processed), 0.92)
  }

  private func rms(_ samples: [Float]) -> Float {
    let sumSquares = samples.reduce(0.0) { partialResult, sample in
      let value = Double(sample)
      return partialResult + (value * value)
    }
    return Float(sqrt(sumSquares / Double(samples.count)))
  }

  private func peak(_ samples: [Float]) -> Float {
    samples.reduce(0) { max($0, Swift.abs($1)) }
  }
}
