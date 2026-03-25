import XCTest
@testable import ListenSDRCore

final class DeferredSessionRestoreCoreTests: XCTestCase {
  func testConstantsMatchCanonicalFixtures() throws {
    let fixture: DeferredSessionRestoreCoreFixtureSet = try FixtureLoader.load(
      "deferred-session-restore-core-cases.json"
    )

    for testCase in fixture.constantCases {
      XCTAssertEqual(
        DeferredSessionRestoreCore.deadlineSeconds,
        testCase.expectedDeadlineSeconds,
        accuracy: 0.0001,
        testCase.label
      )
      XCTAssertEqual(
        DeferredSessionRestoreCore.pollIntervalSeconds,
        testCase.expectedPollIntervalSeconds,
        accuracy: 0.0001,
        testCase.label
      )
    }
  }

  func testStatusRulesMatchCanonicalFixtures() throws {
    let fixture: DeferredSessionRestoreCoreFixtureSet = try FixtureLoader.load(
      "deferred-session-restore-core-cases.json"
    )

    for testCase in fixture.statusCases {
      let status = DeferredSessionRestoreCore.Status(
        isConnected: testCase.isConnected,
        isTargetProfileConnected: testCase.isTargetProfileConnected,
        canApplyLocalTuning: testCase.canApplyLocalTuning,
        deadlineReached: testCase.deadlineReached
      )

      XCTAssertEqual(
        testCase.expected.shouldApply,
        DeferredSessionRestoreCore.shouldApply(status: status),
        testCase.label
      )
      XCTAssertEqual(
        testCase.expected.shouldContinueWaiting,
        DeferredSessionRestoreCore.shouldContinueWaiting(status: status),
        testCase.label
      )
    }
  }
}
