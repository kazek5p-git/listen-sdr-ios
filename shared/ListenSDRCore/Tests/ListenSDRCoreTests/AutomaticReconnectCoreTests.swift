import XCTest
@testable import ListenSDRCore

final class AutomaticReconnectCoreTests: XCTestCase {
  func testDelaysMatchCanonicalFixtures() throws {
    let fixture: AutomaticReconnectCoreFixtureSet = try FixtureLoader.load(
      "automatic-reconnect-core-cases.json"
    )

    for testCase in fixture.delayCases {
      XCTAssertEqual(
        testCase.expectedDelaySeconds,
        AutomaticReconnectCore.delaySeconds(forAttemptNumber: testCase.attemptNumber),
        accuracy: 0.0001,
        testCase.label
      )
    }
  }

  func testRetryWindowMatchesCanonicalFixtures() throws {
    let fixture: AutomaticReconnectCoreFixtureSet = try FixtureLoader.load(
      "automatic-reconnect-core-cases.json"
    )

    XCTAssertEqual(
      fixture.expectedRetryWindowSeconds,
      AutomaticReconnectCore.retryWindowSeconds,
      accuracy: 0.0001
    )

    for testCase in fixture.retryCases {
      XCTAssertEqual(
        testCase.expectedShouldContinueRetrying,
        AutomaticReconnectCore.shouldContinueRetrying(elapsedSeconds: testCase.elapsedSeconds),
        testCase.label
      )
    }
  }
}
