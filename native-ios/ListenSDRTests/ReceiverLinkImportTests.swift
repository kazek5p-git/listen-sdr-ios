import XCTest
@testable import ListenSDR

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
}
