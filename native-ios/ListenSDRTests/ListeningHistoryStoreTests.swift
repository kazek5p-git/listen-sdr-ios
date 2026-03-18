import XCTest
@testable import ListenSDR

final class ListeningHistoryStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "ListenSDRTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  @MainActor
  func testRecordingReceiverDeduplicatesByEndpointIdentity() {
    let store = ListeningHistoryStore(defaults: defaults, namespace: suiteName)
    let profile = SDRConnectionProfile(
      name: "Test FM-DX",
      backend: .fmDxWebserver,
      host: "example.com",
      port: 8080,
      useTLS: false,
      path: "/"
    )

    store.recordReceiver(profile)
    store.recordReceiver(profile)

    XCTAssertEqual(store.recentReceivers.count, 1)
    XCTAssertEqual(store.recentReceivers.first?.receiverName, "Test FM-DX")
  }

  @MainActor
  func testRecordingListeningMergesStationTitleForSameReceiverAndFrequency() {
    let store = ListeningHistoryStore(defaults: defaults, namespace: suiteName)
    let profile = SDRConnectionProfile(
      name: "Krakow FM-DX",
      backend: .fmDxWebserver,
      host: "krakow.example",
      port: 8080,
      useTLS: false,
      path: "/"
    )

    store.recordListening(profile: profile, frequencyHz: 98_400_000, mode: .fm, stationTitle: nil)
    store.recordListening(profile: profile, frequencyHz: 98_400_000, mode: .fm, stationTitle: "Rave FM")

    XCTAssertEqual(store.recentListening.count, 1)
    XCTAssertEqual(store.recentListening.first?.stationTitle, "Rave FM")
    XCTAssertEqual(store.recentListening.first?.frequencyHz, 98_400_000)
  }

  @MainActor
  func testRecordingRecentFrequencyMergesStationTitleForSameReceiverAndFrequency() {
    let store = ListeningHistoryStore(defaults: defaults, namespace: suiteName)
    let profile = SDRConnectionProfile(
      name: "Katowice OpenWebRX",
      backend: .openWebRX,
      host: "katowice.example",
      port: 8073,
      useTLS: false,
      path: "/"
    )

    store.recordRecentFrequency(profile: profile, frequencyHz: 145_500_000, mode: .nfm, stationTitle: nil)
    store.recordRecentFrequency(profile: profile, frequencyHz: 145_500_000, mode: .nfm, stationTitle: "SR9V")

    XCTAssertEqual(store.recentFrequencies.count, 1)
    XCTAssertEqual(store.recentFrequencies.first?.stationTitle, "SR9V")
    XCTAssertEqual(store.recentFrequencies.first?.frequencyHz, 145_500_000)
    XCTAssertEqual(store.recentFrequencies.first?.mode, .nfm)
  }

  @MainActor
  func testRecentFrequenciesAreStoredSeparatelyPerReceiver() {
    let store = ListeningHistoryStore(defaults: defaults, namespace: suiteName)
    let firstProfile = SDRConnectionProfile(
      name: "Bytom FM-DX",
      backend: .fmDxWebserver,
      host: "bytom.example",
      port: 8080,
      useTLS: false,
      path: "/"
    )
    let secondProfile = SDRConnectionProfile(
      name: "Krakow FM-DX",
      backend: .fmDxWebserver,
      host: "krakow.example",
      port: 8080,
      useTLS: false,
      path: "/"
    )

    store.recordRecentFrequency(profile: firstProfile, frequencyHz: 98_400_000, mode: .fm, stationTitle: "Radio Zet")
    store.recordRecentFrequency(profile: secondProfile, frequencyHz: 98_400_000, mode: .fm, stationTitle: "Radio Zet")

    XCTAssertEqual(store.recentFrequencies.count, 2)
    XCTAssertEqual(Set(store.recentFrequencies.map(\.receiverName)), Set(["Bytom FM-DX", "Krakow FM-DX"]))
  }
}
