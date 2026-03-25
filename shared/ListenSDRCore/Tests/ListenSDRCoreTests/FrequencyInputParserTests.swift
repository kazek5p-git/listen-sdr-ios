import XCTest
@testable import ListenSDRCore

final class FrequencyInputParserTests: XCTestCase {
  func testParsesFMBroadcastShortcutWithoutDecimalSeparator() {
    let value = FrequencyInputParser.parseHz(from: "985", context: .fmBroadcast)
    XCTAssertEqual(value, 98_500_000)
  }

  func testParsesShortwaveKilohertzShortcut() {
    let value = FrequencyInputParser.parseHz(from: "7050", context: .shortwave)
    XCTAssertEqual(value, 7_050_000)
  }

  func testParsesBandAwareUHFValueWithMultipleSeparators() {
    let value = FrequencyInputParser.parseHz(
      from: "446.156.25",
      context: .generic,
      preferredRangeHz: 430_000_000...440_000_000
    )
    XCTAssertEqual(value, 446_156_250)
  }
}
