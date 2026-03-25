import XCTest
@testable import ListenSDRCore

final class ReceiverIdentityTests: XCTestCase {
  func testMatchesCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("receiver-identity-cases.json", as: ReceiverIdentityFixtureSet.self)

    for testCase in fixture.cases {
      XCTAssertEqual(
        ReceiverIdentity.key(
          backend: try SDRBackend(fixtureValue: testCase.backend),
          host: testCase.host,
          port: testCase.port,
          useTLS: testCase.useTLS,
          path: testCase.path
        ),
        testCase.expectedKey,
        testCase.label
      )
    }
  }
}
