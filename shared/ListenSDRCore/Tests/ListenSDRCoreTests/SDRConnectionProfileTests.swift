import XCTest
@testable import ListenSDRCore

final class SDRConnectionProfileTests: XCTestCase {
  func testNormalizesPathAndEndpointDescription() {
    let profile = SDRConnectionProfile(
      id: UUID(uuidString: "0F1E2D3C-4B5A-6978-8091-A2B3C4D5E6F7")!,
      name: "Demo",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 443,
      useTLS: true,
      path: "radio"
    )

    XCTAssertEqual(profile.normalizedPath, "/radio")
    XCTAssertEqual(profile.endpointDescription, "https://receiver.example:443/radio")
  }

  func testApplyBackendChangeUpdatesDefaultPort() {
    var profile = SDRConnectionProfile(
      name: "Demo",
      backend: .kiwiSDR,
      host: "receiver.example",
      port: 8073
    )

    profile.applyBackendChange(.fmDxWebserver)

    XCTAssertEqual(profile.backend, .fmDxWebserver)
    XCTAssertEqual(profile.port, 8080)
  }

  func testApplyTLSChangeKeepsCustomPortButMovesDefaultPort() {
    var profile = SDRConnectionProfile(
      name: "Demo",
      backend: .fmDxWebserver,
      host: "receiver.example",
      port: 8080,
      useTLS: false
    )

    profile.applyTLSChange(true)
    XCTAssertTrue(profile.useTLS)
    XCTAssertEqual(profile.port, 443)

    profile.port = 9000
    profile.applyTLSChange(false)
    XCTAssertFalse(profile.useTLS)
    XCTAssertEqual(profile.port, 9000)
  }
}
