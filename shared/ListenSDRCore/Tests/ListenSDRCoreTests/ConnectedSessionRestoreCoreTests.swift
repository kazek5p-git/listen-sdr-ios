import XCTest
@testable import ListenSDRCore

final class ConnectedSessionRestoreCoreTests: XCTestCase {
  func testActionsMatchCanonicalFixtures() throws {
    let fixture: ConnectedSessionRestoreCoreFixtureSet = try FixtureLoader.load(
      "connected-session-restore-core-cases.json"
    )

    for testCase in fixture.cases {
      let backend = try testCase.backend.map { try SDRBackend(fixtureValue: $0) }
      let status = ConnectedSessionRestoreCore.Status(
        hasPendingRestore: testCase.frequencyHz != nil || testCase.mode != nil,
        initialTuningSyncStatus: .init(
          backend: backend,
          hasInitialServerTuningSync: testCase.hasInitialServerTuningSync,
          deadlineReached: testCase.deadlineReached
        )
      )

      XCTAssertEqual(
        try ConnectedSessionRestoreAction(fixtureValue: testCase.expectedAction),
        ConnectedSessionRestoreCore.action(status: status),
        testCase.label
      )
    }
  }
}
