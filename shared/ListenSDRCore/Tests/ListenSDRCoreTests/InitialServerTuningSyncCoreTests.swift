import XCTest
@testable import ListenSDRCore

final class InitialServerTuningSyncCoreTests: XCTestCase {
  func testDeadlineRulesMatchCanonicalFixtures() throws {
    let fixture: InitialServerTuningSyncCoreFixtureSet = try FixtureLoader.load(
      "initial-server-tuning-sync-core-cases.json"
    )

    for testCase in fixture.deadlineCases {
      let backend = try testCase.backend.map { try SDRBackend(fixtureValue: $0) }
      let actualSeconds = InitialServerTuningSyncCore.initialSyncDeadlineSeconds(
        for: backend
      )

      if let expectedSeconds = testCase.expectedSeconds {
        guard let actualSeconds else {
          XCTFail("\(testCase.label): expected deadline \(expectedSeconds), got nil")
          continue
        }
        XCTAssertEqual(actualSeconds, expectedSeconds, accuracy: 0.0001, testCase.label)
      } else {
        XCTAssertNil(actualSeconds, testCase.label)
      }
    }
  }

  func testStatusRulesMatchCanonicalFixtures() throws {
    let fixture: InitialServerTuningSyncCoreFixtureSet = try FixtureLoader.load(
      "initial-server-tuning-sync-core-cases.json"
    )

    for testCase in fixture.statusCases {
      let backend = try testCase.backend.map { try SDRBackend(fixtureValue: $0) }
      let status = InitialServerTuningSyncCore.Status(
        backend: backend,
        hasInitialServerTuningSync: testCase.hasInitialServerTuningSync,
        deadlineReached: testCase.deadlineReached
      )

      XCTAssertEqual(
        testCase.expected.requiresInitialServerTuningSync,
        InitialServerTuningSyncCore.requiresInitialServerTuningSync(for: status.backend),
        testCase.label
      )
      XCTAssertEqual(
        testCase.expected.canApplyLocalTuning,
        InitialServerTuningSyncCore.canApplyLocalTuning(status: status),
        testCase.label
      )
      XCTAssertEqual(
        testCase.expected.isWaitingForInitialServerTuningSync,
        InitialServerTuningSyncCore.isWaitingForInitialServerTuningSync(status: status),
        testCase.label
      )
      XCTAssertEqual(
        testCase.expected.shouldApplyInitialLocalFallback,
        InitialServerTuningSyncCore.shouldApplyInitialLocalFallback(status: status),
        testCase.label
      )
    }
  }
}
