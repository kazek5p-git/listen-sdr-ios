import XCTest
@testable import ListenSDRCore

final class RuntimeAdjustedSettingsCoreTests: XCTestCase {
  func testAdjustedStateMatchesCanonicalFixtures() throws {
    let fixture: RuntimeAdjustedSettingsCoreFixtureSet = try FixtureLoader.load(
      "runtime-adjusted-settings-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedState,
        RuntimeAdjustedSettingsCore.adjustedState(
          backend: testCase.backend,
          mode: testCase.mode,
          squelchEnabled: testCase.squelchEnabled,
          isSquelchLockedByScanner: testCase.isSquelchLockedByScanner
        ),
        testCase.label
      )
    }
  }

  func testEffectiveSquelchEnabledMatchesCanonicalFixtures() throws {
    let fixture: RuntimeAdjustedSettingsCoreFixtureSet = try FixtureLoader.load(
      "runtime-adjusted-settings-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedState.squelchEnabled,
        RuntimeAdjustedSettingsCore.effectiveSquelchEnabled(
          storedEnabled: testCase.squelchEnabled,
          isLockedByScanner: testCase.isSquelchLockedByScanner
        ),
        testCase.label
      )
    }
  }
}

private struct RuntimeAdjustedSettingsCoreFixtureSet: Decodable {
  let cases: [RuntimeAdjustedSettingsCoreFixtureCase]
}

private struct RuntimeAdjustedSettingsCoreFixtureCase: Decodable {
  let label: String
  let backend: SDRBackend
  let mode: DemodulationMode
  let squelchEnabled: Bool
  let isSquelchLockedByScanner: Bool
  let expectedState: RuntimeAdjustedSettingsCore.State
}
