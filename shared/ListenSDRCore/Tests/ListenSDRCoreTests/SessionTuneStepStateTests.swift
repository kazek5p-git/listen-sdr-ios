import XCTest
@testable import ListenSDRCore

final class SessionTuneStepStateTests: XCTestCase {
  func testTuneStepStateMatchesCanonicalFixtures() throws {
    let fixture: SessionTuneStepStateFixtureSet = try FixtureLoader.load("session-tune-step-state-cases.json")

    for entry in fixture.stateCases {
      let context = try makeContext(entry.context)
      let state = SessionTuningCore.tuneStepState(
        preferredStepHz: entry.preferredStepHz,
        preferenceMode: try TuneStepPreferenceMode(fixtureValue: entry.preferenceMode),
        context: context
      )

      XCTAssertEqual(state.tuneStepHz, entry.expectedTuneStepHz, entry.label)
      XCTAssertEqual(state.preferredTuneStepHz, entry.expectedPreferredTuneStepHz, entry.label)
    }
  }

  func testManualTuneStepSelectionMatchesCanonicalFixtures() throws {
    let fixture: SessionTuneStepStateFixtureSet = try FixtureLoader.load("session-tune-step-state-cases.json")

    for entry in fixture.manualSelectionCases {
      let context = try makeContext(entry.context)
      let state = SessionTuningCore.manualTuneStepState(
        requestedStepHz: entry.requestedStepHz,
        context: context
      )

      XCTAssertEqual(state.preferenceMode, .manual, entry.label)
      XCTAssertEqual(state.tuneStepHz, entry.expectedTuneStepHz, entry.label)
      XCTAssertEqual(state.preferredTuneStepHz, entry.expectedPreferredTuneStepHz, entry.label)
    }
  }

  private func makeContext(_ fixture: BandTuningCoreFixtureSet.Context?) throws -> BandTuningContext? {
    guard let fixture else { return nil }
    return BandTuningContext(
      backend: try SDRBackend(fixtureValue: fixture.backend),
      frequencyHz: fixture.frequencyHz,
      mode: try DemodulationMode(fixtureValue: fixture.mode),
      bandName: fixture.bandName,
      bandTags: fixture.bandTags
    )
  }
}
