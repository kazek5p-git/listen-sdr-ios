import XCTest
@testable import ListenSDR

final class AudioDecodersTests: XCTestCase {
  func testDownmixInterleavedStereoPcmAveragesStereoFrames() {
    let stereo: [Int16] = [1000, -1000, 2000, 4000, -3000, -1000]

    let mono = downmixInterleavedStereoPCM(stereo)

    XCTAssertEqual(mono, [0, 3000, -2000])
  }
}
