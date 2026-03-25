import XCTest
@testable import ListenSDRCore

final class SavedSettingsSnapshotCoreTests: XCTestCase {
  func testCreatedSnapshotMatchesCanonicalFixtures() throws {
    let fixture: SavedSettingsSnapshotCoreFixtureSet = try FixtureLoader.load(
      "saved-settings-snapshot-core-cases.json"
    )

    for testCase in fixture.createCases {
      let created = SavedSettingsSnapshotCore.createdSnapshot(
        from: .init(
          frequencyHz: testCase.current.frequencyHz,
          dxNightModeEnabled: testCase.current.dxNightModeEnabled,
          autoFilterProfileEnabled: testCase.current.autoFilterProfileEnabled
        )
      )

      XCTAssertEqual(created.frequencyHz, testCase.expected.frequencyHz, testCase.label)
      XCTAssertEqual(created.dxNightModeEnabled, testCase.expected.dxNightModeEnabled, testCase.label)
      XCTAssertEqual(created.autoFilterProfileEnabled, testCase.expected.autoFilterProfileEnabled, testCase.label)
    }
  }

  func testRestoredSnapshotMatchesCanonicalFixtures() throws {
    let fixture: SavedSettingsSnapshotCoreFixtureSet = try FixtureLoader.load(
      "saved-settings-snapshot-core-cases.json"
    )

    for testCase in fixture.restoreCases {
      let restored = SavedSettingsSnapshotCore.restoredState(
        current: .init(
          frequencyHz: testCase.current.frequencyHz,
          dxNightModeEnabled: testCase.current.dxNightModeEnabled,
          autoFilterProfileEnabled: testCase.current.autoFilterProfileEnabled
        ),
        snapshot: .init(
          frequencyHz: testCase.snapshot.frequencyHz,
          dxNightModeEnabled: testCase.snapshot.dxNightModeEnabled,
          autoFilterProfileEnabled: testCase.snapshot.autoFilterProfileEnabled
        ),
        includeFrequency: testCase.includeFrequency
      )

      XCTAssertEqual(restored.frequencyHz, testCase.expected.frequencyHz, testCase.label)
      XCTAssertEqual(restored.dxNightModeEnabled, testCase.expected.dxNightModeEnabled, testCase.label)
      XCTAssertEqual(restored.autoFilterProfileEnabled, testCase.expected.autoFilterProfileEnabled, testCase.label)
    }
  }
}
