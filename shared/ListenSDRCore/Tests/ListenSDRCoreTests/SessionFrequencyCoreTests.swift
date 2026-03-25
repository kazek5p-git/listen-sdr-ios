import XCTest
@testable import ListenSDRCore

final class SessionFrequencyCoreTests: XCTestCase {
  func testNormalizedFrequencyMatchesCanonicalFixtures() throws {
    let fixture: SessionFrequencyCoreFixtureSet = try FixtureLoader.load("session-frequency-core-cases.json")

    for entry in fixture.normalizedFrequencyCases {
      let backend = try entry.backend.map(SDRBackend.init(fixtureValue:))
      let mode = try DemodulationMode(fixtureValue: entry.mode)

      XCTAssertEqual(
        SessionFrequencyCore.normalizedFrequencyHz(
          entry.inputFrequencyHz,
          backend: backend,
          mode: mode
        ),
        entry.expectedFrequencyHz,
        entry.label
      )
    }
  }

  func testTunedFrequencyMatchesCanonicalFixtures() throws {
    let fixture: SessionFrequencyCoreFixtureSet = try FixtureLoader.load("session-frequency-core-cases.json")

    for entry in fixture.tunedFrequencyCases {
      let backend = try entry.backend.map(SDRBackend.init(fixtureValue:))
      let mode = try DemodulationMode(fixtureValue: entry.mode)

      XCTAssertEqual(
        SessionFrequencyCore.tunedFrequencyHz(
          currentFrequencyHz: entry.currentFrequencyHz,
          stepCount: entry.stepCount,
          tuneStepHz: entry.tuneStepHz,
          backend: backend,
          mode: mode
        ),
        entry.expectedFrequencyHz,
        entry.label
      )
    }
  }
}
