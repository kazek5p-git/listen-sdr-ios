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

  func testNextEvaluationDateTracksStabilityAndMinimumInterval() {
    let gate = StableAnnouncementGate<String>(
      stabilityInterval: { _ in 0.2 },
      minimumInterval: { _ in 0.5 }
    )
    let first = StableAnnouncementCandidate(kind: "station", text: "Station: Radio One")
    let second = StableAnnouncementCandidate(kind: "station", text: "Station: Radio Two")

    XCTAssertNil(gate.evaluate(candidate: first, now: Date(timeIntervalSince1970: 0.0)))
    XCTAssertEqual(
      Date(timeIntervalSince1970: 0.2),
      gate.nextEvaluationDate(candidate: first, now: Date(timeIntervalSince1970: 0.0))
    )
    XCTAssertEqual(first, gate.evaluate(candidate: first, now: Date(timeIntervalSince1970: 0.2)))

    XCTAssertNil(gate.evaluate(candidate: second, now: Date(timeIntervalSince1970: 0.25)))
    XCTAssertEqual(
      Date(timeIntervalSince1970: 0.7),
      gate.nextEvaluationDate(candidate: second, now: Date(timeIntervalSince1970: 0.25))
    )
  }
}
