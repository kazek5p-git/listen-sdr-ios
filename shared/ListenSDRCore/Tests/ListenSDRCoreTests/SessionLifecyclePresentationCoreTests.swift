import XCTest
@testable import ListenSDRCore

final class SessionLifecyclePresentationCoreTests: XCTestCase {
  func testPresentationMatchesCanonicalFixtures() throws {
    let fixture: SessionLifecyclePresentationCoreFixtureSet = try FixtureLoader.load(
      "session-lifecycle-presentation-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedPresentation,
        SessionLifecyclePresentationCore.presentation(
          for: testCase.event,
          backend: testCase.backend
        ),
        testCase.label
      )
    }
  }
}

private struct SessionLifecyclePresentationCoreFixtureSet: Decodable {
  let cases: [SessionLifecyclePresentationCoreFixtureCase]
}

private struct SessionLifecyclePresentationCoreFixtureCase: Decodable {
  let label: String
  let event: SessionLifecyclePresentationEvent
  let backend: SDRBackend?
  let expectedPresentation: SessionLifecyclePresentation
}
