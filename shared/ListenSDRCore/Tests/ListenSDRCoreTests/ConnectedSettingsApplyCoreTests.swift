import XCTest
@testable import ListenSDRCore

final class ConnectedSettingsApplyCoreTests: XCTestCase {
  func testActionsMatchCanonicalFixtures() throws {
    let fixture: ConnectedSettingsApplyCoreFixtureSet = try FixtureLoader.load(
      "connected-settings-apply-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedAction,
        ConnectedSettingsApplyCore.action(for: testCase.status),
        testCase.label
      )
    }
  }
}

private struct ConnectedSettingsApplyCoreFixtureSet: Decodable {
  let cases: [ConnectedSettingsApplyCoreFixtureCase]
}

private struct ConnectedSettingsApplyCoreFixtureCase: Decodable {
  let label: String
  let status: ConnectedSettingsApplyCore.Status
  let expectedAction: ConnectedSettingsApplyCore.Action
}
