import XCTest
@testable import ListenSDRCore

final class LiveAudioAnalysisRefreshCoreTests: XCTestCase {
  func testRefreshRulesMatchCanonicalFixtures() throws {
    let fixture: LiveAudioAnalysisRefreshCoreFixtureSet = try FixtureLoader.load(
      "live-audio-analysis-refresh-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedShouldRefresh,
        LiveAudioAnalysisRefreshCore.shouldRefresh(
          policy: testCase.policy,
          elapsedSecondsSinceLastReducedActivityRefresh: testCase.elapsedSecondsSinceLastReducedActivityRefresh
        ),
        testCase.label
      )
    }
  }
}

private struct LiveAudioAnalysisRefreshCoreFixtureSet: Decodable {
  let cases: [LiveAudioAnalysisRefreshCoreFixtureCase]
}

private struct LiveAudioAnalysisRefreshCoreFixtureCase: Decodable {
  let label: String
  let policy: BackendRuntimePolicyCore.Policy
  let elapsedSecondsSinceLastReducedActivityRefresh: Double
  let expectedShouldRefresh: Bool
}
