import XCTest
@testable import ListenSDRCore

final class ReceiverCountryResolverTests: XCTestCase {
  func testMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load(
      "receiver-country-resolver-cases.json",
      as: ReceiverCountryResolverFixtureSet.self
    )

    for testCase in fixture.countryCodeCases {
      XCTAssertEqual(
        ReceiverCountryResolver.resolvedCountryCode(
          countryCode: testCase.countryCode,
          countryName: testCase.countryName
        ),
        testCase.expectedCode,
        testCase.label
      )
    }

    for testCase in fixture.countryNameCases {
      XCTAssertEqual(
        ReceiverCountryResolver.resolvedCountryCode(fromCountryName: testCase.rawValue),
        testCase.expectedCode,
        testCase.label
      )
    }

    for testCase in fixture.metadataCases {
      XCTAssertEqual(
        ReceiverCountryResolver.resolvedCountryCode(
          fromMetadataLabel: testCase.locationLabel,
          host: testCase.host
        ),
        testCase.expectedCode,
        testCase.label
      )
    }
  }
}
