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
