import XCTest
@testable import ListenSDR

private final class InMemoryProfilePasswordStore: ProfilePasswordStore {
  var passwords: [UUID: String] = [:]
  var failingProfileIDs: Set<UUID> = []

  func password(for profileID: UUID) -> String? {
    passwords[profileID]
  }

  @discardableResult
  func store(password: String, for profileID: UUID) -> Bool {
    guard !failingProfileIDs.contains(profileID) else {
      return false
    }
    passwords[profileID] = password
    return true
  }

  @discardableResult
  func removePassword(for profileID: UUID) -> Bool {
    passwords.removeValue(forKey: profileID)
    return true
  }
}

final class ReceiverIdentityTests: XCTestCase {
  func testReceiverIdentityNormalizesHostAndPath() {
    let lhs = ReceiverIdentity.key(
      backend: .fmDxWebserver,
      host: " Example.COM ",
      port: 8080,
      useTLS: false,
      path: "radio"
    )
    let rhs = ReceiverIdentity.key(
      backend: .fmDxWebserver,
      host: "example.com",
      port: 8080,
      useTLS: false,
      path: "/RADIO"
    )

    XCTAssertEqual(lhs, rhs)
  }
}

final class ProfileStoreSecretPersistenceTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!
  private var passwordStore: InMemoryProfilePasswordStore!

  override func setUp() {
    super.setUp()
    suiteName = "ListenSDR.ProfileStoreSecretPersistenceTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
    passwordStore = InMemoryProfilePasswordStore()
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    passwordStore = nil
    super.tearDown()
  }

  func testProfileStorePersistsPasswordsOutsideUserDefaults() throws {
    let profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "example.com",
      port: 8080,
      password: "sekret-admin"
    )

    let store = ProfileStore(defaults: defaults, passwordStore: passwordStore)
    store.upsert(profile)

    let persistedProfiles = try decodeStoredProfiles()
    XCTAssertEqual(persistedProfiles.count, 1)
    XCTAssertEqual(persistedProfiles[0].password, "")
    XCTAssertEqual(passwordStore.passwords[profile.id], "sekret-admin")

    let reloaded = ProfileStore(defaults: defaults, passwordStore: passwordStore)
    XCTAssertEqual(reloaded.selectedProfile?.password, "sekret-admin")
  }

  func testProfileStoreMigratesLegacyPasswordsFromUserDefaults() throws {
    let legacyProfile = SDRConnectionProfile(
      name: "Legacy FM-DX",
      backend: .fmDxWebserver,
      host: "legacy.example.com",
      port: 8080,
      password: "legacy-secret"
    )
    let rawData = try JSONEncoder().encode([legacyProfile])
    defaults.set(rawData, forKey: "ListenSDR.profiles.v1")

    let store = ProfileStore(defaults: defaults, passwordStore: passwordStore)

    XCTAssertEqual(store.selectedProfile?.password, "legacy-secret")
    XCTAssertEqual(passwordStore.passwords[legacyProfile.id], "legacy-secret")

    let persistedProfiles = try decodeStoredProfiles()
    XCTAssertEqual(persistedProfiles[0].password, "")
  }

  func testProfileStoreKeepsPasswordInDefaultsWhenSecretStoreWriteFails() throws {
    let profile = SDRConnectionProfile(
      name: "Fallback FM-DX",
      backend: .fmDxWebserver,
      host: "fallback.example.com",
      port: 8080,
      password: "fallback-secret"
    )
    passwordStore.failingProfileIDs.insert(profile.id)

    let store = ProfileStore(defaults: defaults, passwordStore: passwordStore)
    store.upsert(profile)

    let persistedProfiles = try decodeStoredProfiles()
    XCTAssertEqual(persistedProfiles[0].password, "fallback-secret")
    XCTAssertNil(passwordStore.passwords[profile.id])
  }

  private func decodeStoredProfiles() throws -> [SDRConnectionProfile] {
    guard let rawData = defaults.data(forKey: "ListenSDR.profiles.v1") else {
      XCTFail("Expected persisted profiles data.")
      return []
    }
    return try JSONDecoder().decode([SDRConnectionProfile].self, from: rawData)
  }
}

final class ListenSDRNetworkIdentityTests: XCTestCase {
  func testNetworkIdentityConstantsMatchExpectedPlatformName() {
    XCTAssertEqual(ListenSDRNetworkIdentity.clientName, "Listen SDR for iOS")
    XCTAssertEqual(ListenSDRNetworkIdentity.userAgent, "Listen SDR for iOS")
    XCTAssertEqual(
      ListenSDRNetworkIdentity.openWebRXHandshake,
      "SERVER DE CLIENT client=Listen SDR for iOS type=receiver"
    )
  }

  func testKiwiIdentityFallsBackToAppNameWhenUsernameIsBlank() {
    XCTAssertEqual(
      ListenSDRNetworkIdentity.kiwiIdentUser(username: "   "),
      "Listen%20SDR%20for%20iOS"
    )
  }

  func testKiwiIdentityPreservesExplicitUsername() {
    XCTAssertEqual(
      ListenSDRNetworkIdentity.kiwiIdentUser(username: "  Operator 1  "),
      "Operator%201"
    )
  }

  func testFmdxUserAgentIncludesPlatformTokensAndAppIdentity() {
    let userAgent = ListenSDRNetworkIdentity.fmdxUserAgent(
      platformToken: "iPhone",
      systemVersion: "26.4"
    )

    XCTAssertTrue(userAgent.contains("iPhone"))
    XCTAssertTrue(userAgent.contains("OS 26_4"))
    XCTAssertTrue(userAgent.contains("Mobile/15E148"))
    XCTAssertTrue(userAgent.contains("Listen SDR for iOS"))
  }
}
