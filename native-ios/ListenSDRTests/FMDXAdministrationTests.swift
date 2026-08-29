import Foundation
import XCTest
@testable import ListenSDR

final class FMDXAdministrationTests: XCTestCase {
  func testSetupURLKeepsProfilePathAndUsesTLS() throws {
    let profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "radio.example.com",
      port: 8443,
      useTLS: true,
      path: "/station/"
    )

    let url = try FMDXAdministration.setupURL(for: profile)

    XCTAssertEqual(url.absoluteString, "https://radio.example.com:8443/station/setup")
  }

  func testOnlyFMDXProfilesCanOpenAdministration() {
    let fmdxProfile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "radio.example.com",
      port: 8080
    )
    let kiwiProfile = SDRConnectionProfile(
      name: "Kiwi",
      backend: .kiwiSDR,
      host: "radio.example.com",
      port: 8073
    )

    XCTAssertTrue(FMDXAdministration.canAdminister(fmdxProfile))
    XCTAssertFalse(FMDXAdministration.canAdminister(kiwiProfile))
  }

  func testSetupURLRejectsEmptyHost() {
    let profile = SDRConnectionProfile(
      name: "FM-DX",
      backend: .fmDxWebserver,
      host: "",
      port: 8080
    )

    XCTAssertThrowsError(try FMDXAdministration.setupURL(for: profile))
  }

  func testAdministrationPageMarkerRejectsLoginPage() {
    XCTAssertTrue(
      FMDXAdministration.isAdministrationPage(
        "<script src=\"js/setup.js\"></script><input id=\"password-adminPass\">"
      )
    )
    XCTAssertFalse(
      FMDXAdministration.isAdministrationPage(
        "<script src=\"js/settings.js\"></script><form id=\"login-form\"></form>"
      )
    )
  }

  func testSessionCookieExportExcludesPersistentCookies() throws {
    let authenticationCookie = try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: "radio.example.com",
        .path: "/",
        .name: "connect.sid",
        .value: "secret",
        .expires: Date(timeIntervalSinceNow: 3600)
      ])
    )
    let persistentCookie = try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: "radio.example.com",
        .path: "/",
        .name: "theme",
        .value: "dark",
        .expires: Date(timeIntervalSinceNow: 3600)
      ])
    )

    let exported = FMDXAdministration.sessionCookies(
      from: [authenticationCookie, persistentCookie]
    )

    XCTAssertEqual(exported.map(\.name), ["connect.sid"])
    XCTAssertFalse(authenticationCookie.isSessionOnly)
    XCTAssertFalse(persistentCookie.isSessionOnly)
  }

  func testLoginRequestUsesJsonPost() throws {
    let url = try XCTUnwrap(URL(string: "https://radio.example.com/login"))
    let request = try URLRequest.listenSDRFMDXLoginRequest(
      url: url,
      password: "test-password",
      platformToken: "iPhone",
      systemVersion: "17.5"
    )

    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let body = try XCTUnwrap(request.httpBody)
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: String]
    )
    XCTAssertEqual(payload["password"], "test-password")
  }
}
