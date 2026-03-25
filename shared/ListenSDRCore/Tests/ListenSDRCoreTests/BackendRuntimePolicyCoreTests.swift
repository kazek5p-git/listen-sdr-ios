import XCTest
@testable import ListenSDRCore

final class BackendRuntimePolicyCoreTests: XCTestCase {
  func testPoliciesMatchCanonicalFixtures() throws {
    let fixture: BackendRuntimePolicyCoreFixtureSet = try FixtureLoader.load(
      "backend-runtime-policy-core-cases.json"
    )

    for testCase in fixture.cases {
      XCTAssertEqual(
        testCase.expectedPolicy,
        BackendRuntimePolicyCore.policy(
          isForegroundActive: testCase.isForegroundActive,
          isReceiverTabSelected: testCase.isReceiverTabSelected
        ),
        testCase.label
      )
    }
  }
}

private struct BackendRuntimePolicyCoreFixtureSet: Decodable {
  let cases: [BackendRuntimePolicyCoreFixtureCase]
}

private struct BackendRuntimePolicyCoreFixtureCase: Decodable {
  let label: String
  let isForegroundActive: Bool
  let isReceiverTabSelected: Bool
  let expectedPolicy: BackendRuntimePolicyCore.Policy
}
