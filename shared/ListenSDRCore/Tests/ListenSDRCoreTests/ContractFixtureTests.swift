import Foundation
import XCTest
@testable import ListenSDRCore

final class ContractFixtureTests: XCTestCase {
  func testDecodesCanonicalProfileContractFixture() throws {
    let profile = try FixtureLoader.load(
      "ios-sdr-connection-profile.json",
      as: SDRConnectionProfile.self
    )

    XCTAssertEqual(profile.id.uuidString.lowercased(), "0f1e2d3c-4b5a-6978-8091-a2b3c4d5e6f7")
    XCTAssertEqual(profile.backend, .fmDxWebserver)
    XCTAssertEqual(profile.port, 443)
    XCTAssertTrue(profile.useTLS)
    XCTAssertEqual(profile.path, "/radio")
    XCTAssertEqual(profile.username, "demo")
    XCTAssertEqual(profile.password, "secret")
  }

  func testDecodesCanonicalSettingsContractFixture() throws {
    let settings = try FixtureLoader.load(
      "ios-radio-session-settings.json",
      as: PortableSettingsFixture.self
    )

    XCTAssertEqual(settings.mode, "fm")
    XCTAssertEqual(settings.tuneStepPreferenceMode, "automatic")
    XCTAssertEqual(settings.voiceOverRDSAnnouncementMode, "stationOnly")
    XCTAssertEqual(settings.magicTapAction, "toggleRecording")
    XCTAssertEqual(settings.accessibilityInteractionSoundsVolume, 1.5)
    XCTAssertEqual(settings.radiosSearchFiltersVisibility, "whileSearchFieldActive")
    XCTAssertEqual(settings.fmdxAudioMode, "mono")
    XCTAssertTrue(settings.saveFMDXScannerResultsEnabled)
  }
}

private struct PortableSettingsFixture: Decodable {
  let mode: String
  let tuneStepPreferenceMode: String
  let voiceOverRDSAnnouncementMode: String
  let magicTapAction: String
  let accessibilityInteractionSoundsEnabled: Bool
  let accessibilityInteractionSoundsVolume: Double
  let accessibilityInteractionSoundsMutedDuringRecording: Bool
  let radiosSearchFiltersVisibility: String
  let fmdxAudioMode: String
  let saveFMDXScannerResultsEnabled: Bool
}
