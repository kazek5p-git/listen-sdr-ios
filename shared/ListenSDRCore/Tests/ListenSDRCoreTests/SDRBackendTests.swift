import XCTest
@testable import ListenSDRCore

final class SDRBackendTests: XCTestCase {
  func testDefaultPortsMatchBackendRules() {
    XCTAssertEqual(SDRBackend.kiwiSDR.defaultPort, 8073)
    XCTAssertEqual(SDRBackend.openWebRX.defaultPort, 8073)
    XCTAssertEqual(SDRBackend.fmDxWebserver.defaultPort(useTLS: false), 8080)
    XCTAssertEqual(SDRBackend.fmDxWebserver.defaultPort(useTLS: true), 443)
  }
}
