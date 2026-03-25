import XCTest
@testable import ListenSDRCore

final class ReceiverDirectoryParsingCoreTests: XCTestCase {
  func testMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load(
      "receiver-directory-parsing-core-cases.json",
      as: ReceiverDirectoryParsingFixtureSet.self
    )

    for testCase in fixture.receiverbookJsonCases {
      let result = Result(catching: { try ReceiverDirectoryParsingCore.extractReceiverbookJSON(from: testCase.html) })

      switch testCase.expectedError {
      case nil:
        XCTAssertEqual(try result.get(), testCase.expectedJSON, testCase.label)
      case let expectedError?:
        let error = try XCTUnwrap(result.failureValue as? ReceiverDirectoryParsingCoreError, testCase.label)
        XCTAssertEqual(error.code, try ReceiverDirectoryParsingCoreErrorCode(fixtureValue: expectedError), testCase.label)
      }
    }

    for testCase in fixture.endpointCases {
      let parsed = ReceiverDirectoryParsingCore.parseEndpoint(from: testCase.input)

      switch testCase.expected {
      case nil:
        XCTAssertNil(parsed, testCase.label)
      case let expected?:
        let endpoint = try XCTUnwrap(parsed, testCase.label)
        XCTAssertEqual(endpoint.host, expected.host, testCase.label)
        XCTAssertEqual(endpoint.port, expected.port, testCase.label)
        XCTAssertEqual(endpoint.path, expected.path, testCase.label)
        XCTAssertEqual(endpoint.useTLS, expected.useTLS, testCase.label)
        XCTAssertEqual(endpoint.absoluteURL, expected.absoluteURL, testCase.label)
      }
    }

    for testCase in fixture.fmdxStatusCases {
      XCTAssertEqual(
        ReceiverDirectoryParsingCore.fmdxStatus(from: testCase.rawValue).rawValue,
        testCase.expected,
        testCase.label
      )
    }

    for testCase in fixture.receiverbookTypeCases {
      XCTAssertEqual(
        ReceiverDirectoryParsingCore.matchesReceiverbookType(
          testCase.value,
          backend: try SDRBackend(fixtureValue: testCase.backend)
        ),
        testCase.expected,
        testCase.label
      )
    }

    for testCase in fixture.probeStatusCases {
      XCTAssertEqual(
        ReceiverDirectoryParsingCore.mapProbeStatus(from: testCase.statusCode).rawValue,
        testCase.expected,
        testCase.label
      )
    }
  }
}

private extension Result {
  var failureValue: Failure? {
    switch self {
    case .success:
      return nil
    case .failure(let error):
      return error
    }
  }
}
