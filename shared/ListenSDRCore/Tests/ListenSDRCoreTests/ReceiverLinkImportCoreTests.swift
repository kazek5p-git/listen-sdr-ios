import XCTest
@testable import ListenSDRCore

final class ReceiverLinkImportCoreTests: XCTestCase {
  func testNormalizedURLAddsSchemeAndDropsQueryAndFragment() throws {
    let url = try ReceiverLinkImportCore.normalizedURL("example.com:8073/owrx/?foo=bar#frag")

    XCTAssertEqual(url.scheme, "http")
    XCTAssertEqual(url.host, "example.com")
    XCTAssertEqual(url.port, 8073)
    XCTAssertEqual(url.path, "/owrx/")
    XCTAssertEqual(url.asString(), "http://example.com:8073/owrx/")
  }

  func testNormalizeInspectableURLPreservesRedirectedPort() {
    let normalized = ReceiverLinkImportCore.normalizeInspectableURL(
      ReceiverImportURL(
        scheme: "https",
        host: "webrx.sytes.net",
        port: 8078,
        path: ""
      )
    )

    XCTAssertEqual(normalized.scheme, "https")
    XCTAssertEqual(normalized.host, "webrx.sytes.net")
    XCTAssertEqual(normalized.port, 8078)
    XCTAssertEqual(normalized.path, "/")
  }

  func testDetectsOpenWebRXFromHTMLMarkers() throws {
    let backend = try ReceiverLinkImportCore.detectBackend(
      urlPath: "/",
      html: #"<html><body>openwebrx <script src="/ws/"></script></body></html>"#
    )

    XCTAssertEqual(backend, .openWebRX)
  }

  func testNormalizesBackendSpecificPaths() {
    XCTAssertEqual(
      ReceiverLinkImportCore.normalizedProfilePath(for: .kiwiSDR, rawPath: "/kiwi"),
      "/"
    )
    XCTAssertEqual(
      ReceiverLinkImportCore.normalizedProfilePath(for: .openWebRX, rawPath: "/ws/"),
      "/"
    )
    XCTAssertEqual(
      ReceiverLinkImportCore.normalizedProfilePath(for: .fmDxWebserver, rawPath: "/receiver/text"),
      "/receiver"
    )
  }

  func testExtractsMeaningfulHTMLTitleAndFiltersBranding() {
    XCTAssertEqual(
      ReceiverLinkImportCore.preferredHTMLTitle(from: "<html><title> Test Receiver </title></html>"),
      "Test Receiver"
    )
    XCTAssertNil(
      ReceiverLinkImportCore.preferredHTMLTitle(from: "<html><title> KiwiSDR Receiver </title></html>")
    )
  }
}
