import XCTest
@testable import ListenSDRCore

final class ConnectionMonitorCoreTests: XCTestCase {
  func testPollIntervalsMatchCanonicalFixtures() throws {
    let fixture: ConnectionMonitorCoreFixtureSet = try FixtureLoader.load(
      "connection-monitor-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedPollIntervalSeconds,
        ConnectionMonitorCore.pollIntervalSeconds(for: testCase.policy),
        accuracy: 0.0001,
        testCase.label
      )
    }
  }
}

private struct ConnectionMonitorCoreFixtureSet: Decodable {
  let cases: [ConnectionMonitorCoreFixtureCase]
}

private struct ConnectionMonitorCoreFixtureCase: Decodable {
  let label: String
  let policy: BackendRuntimePolicyCore.Policy
  let expectedPollIntervalSeconds: Double
}
