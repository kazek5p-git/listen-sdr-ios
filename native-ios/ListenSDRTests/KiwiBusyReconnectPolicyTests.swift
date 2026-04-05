import XCTest
@testable import ListenSDR

final class KiwiBusyReconnectPolicyTests: XCTestCase {
  func testKiwiBusyReconnectDelayStartsAtEightSeconds() {
    XCTAssertEqual(kiwiBusyReconnectDelaySeconds(attemptNumber: 1, penaltyLevel: 1), 8.0)
    XCTAssertEqual(kiwiBusyReconnectDelaySeconds(attemptNumber: 2, penaltyLevel: 1), 12.0)
  }

  func testKiwiBusyReconnectDelayAdvancesWithPenaltyLevel() {
    XCTAssertEqual(kiwiBusyReconnectDelaySeconds(attemptNumber: 1, penaltyLevel: 2), 12.0)
    XCTAssertEqual(kiwiBusyReconnectDelaySeconds(attemptNumber: 1, penaltyLevel: 3), 18.0)
    XCTAssertEqual(kiwiBusyReconnectDelaySeconds(attemptNumber: 3, penaltyLevel: 5), 35.0)
  }
}
