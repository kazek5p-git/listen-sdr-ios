import XCTest
@testable import ListenSDRCore

final class BandTuningCoreTests: XCTestCase {
  func testBandProfilesAndTuneStepsMatchCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("band-tuning-core-cases.json", as: BandTuningCoreFixtureSet.self)

    for fixtureCase in fixture.profileCases {
      let context = BandTuningContext(
        backend: try SDRBackend(fixtureValue: fixtureCase.context.backend),
        frequencyHz: fixtureCase.context.frequencyHz,
        mode: try DemodulationMode(fixtureValue: fixtureCase.context.mode),
        bandName: fixtureCase.context.bandName,
        bandTags: fixtureCase.context.bandTags
      )

      let profile = BandTuningProfiles.resolve(for: context)
      XCTAssertEqual(profile.id, fixtureCase.expectedProfile.id, fixtureCase.label)
      XCTAssertEqual(profile.stepOptionsHz, fixtureCase.expectedProfile.stepOptionsHz, fixtureCase.label)
      XCTAssertEqual(profile.defaultStepHz, fixtureCase.expectedProfile.defaultStepHz, fixtureCase.label)

      XCTAssertEqual(
        SessionTuningCore.availableTuneSteps(for: context),
        fixtureCase.expectedProfile.stepOptionsHz,
        fixtureCase.label
      )
      XCTAssertEqual(
        SessionTuningCore.automaticTuneStep(for: context),
        fixtureCase.expectedAutomaticTuneStepHz,
        fixtureCase.label
      )
      XCTAssertEqual(
        SessionTuningCore.resolvedTuneStep(
          preferredStepHz: fixtureCase.manualPreferredTuneStepHz,
          preferenceMode: .manual,
          context: context
        ),
        fixtureCase.expectedManualTuneStepHz,
        fixtureCase.label
      )
    }
  }

  func testInferredKiwiBandNamesMatchCanonicalFixtures() throws {
    let fixture = try FixtureLoader.load("band-tuning-core-cases.json", as: BandTuningCoreFixtureSet.self)

    for fixtureCase in fixture.kiwiBandNameCases {
      XCTAssertEqual(
        SessionTuningCore.inferredKiwiBandName(for: fixtureCase.frequencyHz),
        fixtureCase.expectedBandName,
        fixtureCase.label
      )
    }
  }

  func testFmdxNoaaBandUsesWeatherChannelTuneProfile() {
    let profile = BandTuningProfiles.resolve(
      for: BandTuningContext(
        backend: .fmDxWebserver,
        frequencyHz: 162_475_000,
        mode: .fm,
        bandName: nil,
        bandTags: []
      )
    )

    XCTAssertEqual(profile.id, "fmdx-noaa")
    XCTAssertEqual(profile.stepOptionsHz, [5_000, 10_000, 12_500, 25_000])
    XCTAssertEqual(profile.defaultStepHz, 25_000)
  }
}
