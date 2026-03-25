import XCTest
@testable import ListenSDR
import ListenSDRCore

final class ReceiverLinkImportTests: XCTestCase {
  func testNormalizeURLAddsHTTPWhenMissingScheme() throws {
    let url = try ReceiverLinkImportDetector.normalizedURL(from: "example.com:8073")

    XCTAssertEqual(url.scheme, "http")
    XCTAssertEqual(url.host(), "example.com")
    XCTAssertEqual(url.port, 8073)
  }

  func testDetectKiwiFromHTMLMarkers() throws {
    let url = URL(string: "http://example.com:8073/")!
    let html = "<html><head><link rel=\"stylesheet\" href=\"kiwisdr.min.css\"></head></html>"

    XCTAssertEqual(try ReceiverLinkImportDetector.detectBackend(from: url, html: html), .kiwiSDR)
  }

  func testDetectOpenWebRXFromHTMLMarkers() throws {
    let url = URL(string: "http://example.com:8073/")!
    let html = "<html><body>OpenWebRX receiver with /ws/ endpoint</body></html>"

    XCTAssertEqual(try ReceiverLinkImportDetector.detectBackend(from: url, html: html), .openWebRX)
  }

  func testNormalizeFMDXPathRemovesTextEndpoint() {
    XCTAssertEqual(
      ReceiverLinkImportDetector.normalizedProfilePath(for: .fmDxWebserver, rawPath: "/text"),
      "/"
    )
  }

  func testNormalizeInspectableURLPreservesRedirectedOpenWebRXPort() {
    let redirected = URL(string: "https://webrx.sytes.net:8078/")!

    let normalized = ReceiverLinkImportDetector.normalizeInspectableURLForTests(redirected)

    XCTAssertEqual(normalized.scheme, "https")
    XCTAssertEqual(normalized.host(), "webrx.sytes.net")
    XCTAssertEqual(normalized.port, 8078)
    XCTAssertEqual(normalized.path, "/")
  }

  func testAdjustImportedProfileForBackendChangeUsesTLSAwareDefaultPort() {
    let original = SDRConnectionProfile(
      name: "Imported",
      backend: .openWebRX,
      host: "receiver.example",
      port: 8078,
      useTLS: true,
      path: "/text"
    )

    let adjusted = ReceiverLinkImportDetector.adjustedProfile(original, for: .fmDxWebserver)

    XCTAssertEqual(adjusted.backend, .fmDxWebserver)
    XCTAssertEqual(adjusted.port, 443)
    XCTAssertEqual(adjusted.path, "/")
  }

  func testAdjustImportedProfileForBackendChangeUsesBackendDefaultPortForHTTP() {
    let original = SDRConnectionProfile(
      name: "Imported",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 8080,
      useTLS: false,
      path: "/audio"
    )

    let adjusted = ReceiverLinkImportDetector.adjustedProfile(original, for: .kiwiSDR)

    XCTAssertEqual(adjusted.backend, .kiwiSDR)
    XCTAssertEqual(adjusted.port, 8073)
    XCTAssertEqual(adjusted.path, "/")
  }

  func testProfileTLSChangeMovesFMDXDefaultPortToHTTPS() {
    var profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 8080,
      useTLS: false
    )

    profile.applyTLSChange(true)

    XCTAssertTrue(profile.useTLS)
    XCTAssertEqual(profile.port, 443)
  }

  func testProfileTLSChangeRestoresFMDXDefaultPortToHTTP() {
    var profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 443,
      useTLS: true
    )

    profile.applyTLSChange(false)

    XCTAssertFalse(profile.useTLS)
    XCTAssertEqual(profile.port, 8080)
  }

  func testProfileTLSChangeKeepsCustomPortWhenProfileUsesManualValue() {
    var profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 8443,
      useTLS: false
    )

    profile.applyTLSChange(true)

    XCTAssertTrue(profile.useTLS)
    XCTAssertEqual(profile.port, 8443)
  }

  func testProfileBackendChangeUsesTLSAwareDefaultPort() {
    var profile = SDRConnectionProfile(
      name: "Imported",
      backend: .kiwiSDR,
      host: "receiver.example",
      port: 8073,
      useTLS: true
    )

    profile.applyBackendChange(.fmDxWebserver)

    XCTAssertEqual(profile.backend, .fmDxWebserver)
    XCTAssertEqual(profile.port, 443)
  }

  func testDirectoryCountryResolverNormalizesExplicitCountryName() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(fromCountryName: "Germany"),
      "DE"
    )
  }

  func testDirectoryCountryResolverInfersCountryFromReceiverbookLabel() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(
        fromMetadataLabel: "Silesia | Poland",
        host: "example.net"
      ),
      "PL"
    )
  }

  func testDirectoryCountryResolverInfersCountryFromUppercaseCodeToken() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(
        fromMetadataLabel: "0-30 MHz SDR | Wels AT",
        host: "example.net"
      ),
      "AT"
    )
  }

  func testDirectoryCountryResolverFallsBackToCountryTLD() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(
        fromMetadataLabel: "SDRPT",
        host: "sdrpt.dynip.sapo.pt"
      ),
      "PT"
    )
  }

  func testDirectoryCountryResolverDoesNotTreatRegionAsCountry() {
    XCTAssertNil(
      ReceiverCountryResolver.resolvedCountryCode(
        fromMetadataLabel: "Northern California SDR",
        host: "example.com"
      )
    )
  }

  func testDirectoryCountryResolverPrefersFMDXCountryCodeOverFormalName() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(
        countryCode: "gb",
        countryName: "United Kingdom of Great Britain and Northern Ireland (the)"
      ),
      "GB"
    )
  }

  func testDirectoryCountryResolverFallsBackToFMDXCountryNameWhenCodeMissing() {
    XCTAssertEqual(
      ReceiverCountryResolver.resolvedCountryCode(
        countryCode: nil,
        countryName: "Hungary"
      ),
      "HU"
    )
  }

  @MainActor
  func testDirectorySearchMatchesDiacriticsAndMultipleFields() {
    let entry = makeDirectoryEntry(
      name: "Radio Śląsk",
      host: "krakow.example.net",
      sourceName: "FMDX.org",
      cityLabel: "Kraków",
      countryLabel: "Polska"
    )

    XCTAssertTrue(ReceiverDirectoryViewModel.matchesSearch(query: "slask", entry: entry))
    XCTAssertTrue(ReceiverDirectoryViewModel.matchesSearch(query: "krakow polska", entry: entry))
    XCTAssertFalse(ReceiverDirectoryViewModel.matchesSearch(query: "berlin", entry: entry))
  }

  @MainActor
  func testAvailableCountryOptionsCanSortFMDXByReceiverCount() throws {
    let defaults = try makeIsolatedDefaults()
    let now = Date()
    let entries = [
      makeDirectoryEntry(id: "pl-1", name: "Poland One", countryLabel: "Poland"),
      makeDirectoryEntry(id: "de-1", name: "Germany One", countryLabel: "Germany"),
      makeDirectoryEntry(id: "pl-2", name: "Poland Two", countryLabel: "Poland")
    ]

    let encoded = try XCTUnwrap(try? JSONEncoder().encode(entries))
    defaults.set(encoded, forKey: ReceiverDirectoryViewModel.cacheEntriesKey)
    defaults.set(now, forKey: ReceiverDirectoryViewModel.cacheRefreshDateKey)

    let viewModel = ReceiverDirectoryViewModel(
      defaults: defaults,
      requestNotificationAuthorization: false
    )
    viewModel.countrySortOption = .receiverCount

    let options = viewModel.availableCountryOptions
    XCTAssertEqual(options.map(\.countryLabel), ["Poland", "Germany"])
    XCTAssertEqual(options.map(\.receiverCount), [2, 1])
    XCTAssertEqual(viewModel.countryDisplayTitle(for: "Poland"), "Poland (2)")
  }

  @MainActor
  func testClearCacheRemovesPersistedDirectoryData() throws {
    let defaults = try makeIsolatedDefaults()
    let entries = [
      makeDirectoryEntry(id: "cache-1", name: "Cached Receiver", countryLabel: "Poland")
    ]

    let encoded = try XCTUnwrap(try? JSONEncoder().encode(entries))
    defaults.set(encoded, forKey: ReceiverDirectoryViewModel.cacheEntriesKey)
    defaults.set(Date(), forKey: ReceiverDirectoryViewModel.cacheRefreshDateKey)

    let viewModel = ReceiverDirectoryViewModel(
      defaults: defaults,
      requestNotificationAuthorization: false
    )

    XCTAssertEqual(viewModel.entries.count, 1)
    XCTAssertNotNil(viewModel.lastRefreshDate)
    XCTAssertTrue(viewModel.canClearCache)

    viewModel.clearCache()

    XCTAssertTrue(viewModel.entries.isEmpty)
    XCTAssertNil(viewModel.lastRefreshDate)
    XCTAssertFalse(viewModel.canClearCache)
    XCTAssertNil(defaults.object(forKey: ReceiverDirectoryViewModel.cacheEntriesKey))
    XCTAssertNil(defaults.object(forKey: ReceiverDirectoryViewModel.cacheRefreshDateKey))
  }

  private func makeDirectoryEntry(
    id: String = UUID().uuidString,
    backend: SDRBackend = .fmDxWebserver,
    name: String,
    host: String = "example.com",
    port: Int = 8080,
    sourceName: String = "FMDX.org",
    cityLabel: String? = nil,
    countryLabel: String? = nil,
    status: ReceiverDirectoryStatus = .available
  ) -> ReceiverDirectoryEntry {
    let locationLabel = [cityLabel, countryLabel]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")

    return ReceiverDirectoryEntry(
      id: id,
      backend: backend,
      name: name,
      host: host,
      port: port,
      path: "/",
      useTLS: false,
      endpointURL: "http://\(host):\(port)/",
      sourceName: sourceName,
      status: status,
      cityLabel: cityLabel,
      countryLabel: countryLabel,
      locationLabel: locationLabel.isEmpty ? nil : locationLabel,
      softwareVersion: "1.0",
      latitude: nil,
      longitude: nil
    )
  }

  private func makeIsolatedDefaults() throws -> UserDefaults {
    let suiteName = "ReceiverLinkImportTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw XCTSkip("Could not create isolated UserDefaults suite.")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
