import XCTest
@testable import ListenSDR

final class StableAnnouncementGateTests: XCTestCase {
  func testStableCandidateMustPersistBeforeAnnouncement() {
    let gate = StableAnnouncementGate<String>(
      stabilityInterval: { _ in 1.0 },
      minimumInterval: { _ in 0.0 }
    )
    let candidate = StableAnnouncementCandidate(kind: "station", text: "Station: Radio One")

    XCTAssertNil(gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 0)))
    XCTAssertNil(gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 0.9)))
    XCTAssertEqual(
      candidate,
      gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 1.0))
    )
  }

  func testChangingCandidateResetsStabilityWindow() {
    let gate = StableAnnouncementGate<String>(
      stabilityInterval: { _ in 1.0 },
      minimumInterval: { _ in 0.0 }
    )

    XCTAssertNil(
      gate.evaluate(
        candidate: StableAnnouncementCandidate(kind: "rt", text: "HELLO WOR"),
        now: Date(timeIntervalSince1970: 0)
      )
    )
    XCTAssertNil(
      gate.evaluate(
        candidate: StableAnnouncementCandidate(kind: "rt", text: "HELLO WORLD"),
        now: Date(timeIntervalSince1970: 0.6)
      )
    )
    XCTAssertNil(
      gate.evaluate(
        candidate: StableAnnouncementCandidate(kind: "rt", text: "HELLO WORLD"),
        now: Date(timeIntervalSince1970: 1.5)
      )
    )
    XCTAssertEqual(
      StableAnnouncementCandidate(kind: "rt", text: "HELLO WORLD"),
      gate.evaluate(
        candidate: StableAnnouncementCandidate(kind: "rt", text: "HELLO WORLD"),
        now: Date(timeIntervalSince1970: 1.6)
      )
    )
  }

  func testSameAnnouncementDoesNotRepeatUntilReset() {
    let gate = StableAnnouncementGate<String>(
      stabilityInterval: { _ in 0.5 },
      minimumInterval: { _ in 0.0 }
    )
    let candidate = StableAnnouncementCandidate(kind: "pi", text: "PI: 1234")

    XCTAssertNil(gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 0)))
    XCTAssertEqual(candidate, gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 0.5)))
    XCTAssertNil(gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 1.5)))
    gate.reset()
    XCTAssertNil(gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 2.0)))
    XCTAssertEqual(candidate, gate.evaluate(candidate: candidate, now: Date(timeIntervalSince1970: 2.5)))
  }
}
