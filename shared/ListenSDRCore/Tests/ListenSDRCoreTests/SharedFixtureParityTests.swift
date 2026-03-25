import XCTest
@testable import ListenSDRCore

final class SharedFixtureParityTests: XCTestCase {
  func testFrequencyInputParserMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("frequency-input-parser-cases.json", as: FrequencyInputParserFixtureSet.self)

    for testCase in fixture.cases {
      let context = try FrequencyInputParser.Context(fixtureValue: testCase.context)
      let preferredRange = testCase.preferredRangeHz.map { $0.lower...$0.upper }
      let parsed = FrequencyInputParser.parseHz(
        from: testCase.text,
        context: context,
        preferredRangeHz: preferredRange
      )

      XCTAssertEqual(parsed, testCase.expectedHz, testCase.label)
    }
  }

  func testFrequencyFormatterMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("frequency-formatter-cases.json", as: FrequencyFormatterFixtureSet.self)

    for testCase in fixture.mhzTextCases {
      XCTAssertEqual(
        FrequencyFormatter.mhzText(fromHz: testCase.hz),
        testCase.expected,
        testCase.label
      )
    }

    for testCase in fixture.tuneStepTextCases {
      XCTAssertEqual(
        FrequencyFormatter.tuneStepText(fromHz: testCase.hz),
        testCase.expected,
        testCase.label
      )
    }
  }

  func testReceiverLinkImportCoreMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("receiver-link-import-core-cases.json", as: ReceiverLinkImportFixtureSet.self)

    for testCase in fixture.normalizedURLCases {
      if let expectedError = testCase.expectedError {
        do {
          _ = try ReceiverLinkImportCore.normalizedURL(testCase.input)
          XCTFail("Expected error for fixture: \(testCase.label)")
        } catch let error as ReceiverLinkImportCoreError {
          XCTAssertEqual(error.code, try ReceiverLinkImportCoreErrorCode(fixtureValue: expectedError), testCase.label)
        }
        continue
      }

      let expected = try XCTUnwrap(testCase.expected, testCase.label)
      let url = try ReceiverLinkImportCore.normalizedURL(testCase.input)
      XCTAssertEqual(url.scheme, expected.scheme, testCase.label)
      XCTAssertEqual(url.userInfo, expected.userInfo, testCase.label)
      XCTAssertEqual(url.host, expected.host, testCase.label)
      XCTAssertEqual(url.port, expected.port, testCase.label)
      XCTAssertEqual(url.path, expected.path, testCase.label)
      XCTAssertEqual(url.asString(), expected.asString, testCase.label)
    }

    for testCase in fixture.normalizeInspectableURLCases {
      let input = ReceiverImportURL(
        scheme: testCase.input.scheme,
        userInfo: testCase.input.userInfo,
        host: testCase.input.host,
        port: testCase.input.port,
        path: testCase.input.path
      )
      let normalized = ReceiverLinkImportCore.normalizeInspectableURL(input)
      XCTAssertEqual(normalized.scheme, testCase.expected.scheme, testCase.label)
      XCTAssertEqual(normalized.userInfo, testCase.expected.userInfo, testCase.label)
      XCTAssertEqual(normalized.host, testCase.expected.host, testCase.label)
      XCTAssertEqual(normalized.port, testCase.expected.port, testCase.label)
      XCTAssertEqual(normalized.path, testCase.expected.path, testCase.label)
      XCTAssertEqual(normalized.asString(), testCase.expected.asString, testCase.label)
    }

    for testCase in fixture.backendDetectionCases {
      if let expectedError = testCase.expectedError {
        do {
          _ = try ReceiverLinkImportCore.detectBackend(urlPath: testCase.urlPath, html: testCase.html)
          XCTFail("Expected detection error for fixture: \(testCase.label)")
        } catch let error as ReceiverLinkImportCoreError {
          XCTAssertEqual(error.code, try ReceiverLinkImportCoreErrorCode(fixtureValue: expectedError), testCase.label)
        }
        continue
      }

      let backend = try ReceiverLinkImportCore.detectBackend(urlPath: testCase.urlPath, html: testCase.html)
      XCTAssertEqual(backend, try ReceiverImportBackend(fixtureValue: testCase.expectedBackend ?? ""), testCase.label)
    }

    for testCase in fixture.normalizedProfilePathCases {
      let backend = try ReceiverImportBackend(fixtureValue: testCase.backend)
      XCTAssertEqual(
        ReceiverLinkImportCore.normalizedProfilePath(for: backend, rawPath: testCase.rawPath),
        testCase.expectedPath,
        testCase.label
      )
    }

    for testCase in fixture.preferredTitleCases {
      XCTAssertEqual(
        ReceiverLinkImportCore.preferredHTMLTitle(from: testCase.html),
        testCase.expectedTitle,
        testCase.label
      )
    }

    for testCase in fixture.fallbackDisplayNameCases {
      XCTAssertEqual(
        ReceiverLinkImportCore.fallbackDisplayName(host: testCase.host),
        testCase.expectedName,
        testCase.label
      )
    }
  }
}
