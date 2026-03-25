import XCTest
@testable import ListenSDRCore

final class FrequencyFormatterTests: XCTestCase {
  func testFormatsMegahertzText() {
    XCTAssertEqual(FrequencyFormatter.mhzText(fromHz: 98_500_000), "98.500 MHz")
  }

  func testFormatsTuneStepTextAcrossUnits() {
    XCTAssertEqual(FrequencyFormatter.tuneStepText(fromHz: 100), "100 Hz")
    XCTAssertEqual(FrequencyFormatter.tuneStepText(fromHz: 25_000), "25 kHz")
    XCTAssertEqual(FrequencyFormatter.tuneStepText(fromHz: 2_500_000), "2.500 MHz")
  }
}
