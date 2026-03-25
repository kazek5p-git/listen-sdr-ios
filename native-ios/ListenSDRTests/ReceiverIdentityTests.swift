import XCTest
@testable import ListenSDR

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
