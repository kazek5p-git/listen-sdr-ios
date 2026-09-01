import Foundation
import SwiftUI
import UIKit
import WebKit

private let fmdxAdministrationSessionCookieName = "connect.sid"

private func isSameFMDXOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
  guard
    let left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
    let right = URLComponents(url: rhs, resolvingAgainstBaseURL: false),
    let leftHost = left.host?.lowercased(),
    let rightHost = right.host?.lowercased(),
    let leftScheme = left.scheme?.lowercased(),
    let rightScheme = right.scheme?.lowercased()
  else {
    return false
  }

  let leftPort = left.port ?? (leftScheme == "https" ? 443 : 80)
  let rightPort = right.port ?? (rightScheme == "https" ? 443 : 80)
  return leftScheme == rightScheme && leftHost == rightHost && leftPort == rightPort
}

private final class FMDXAdministrationRedirectDelegate: NSObject, URLSessionTaskDelegate {
  private let origin: URL

  init(origin: URL) {
    self.origin = origin
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let redirectURL = request.url, isSameFMDXOrigin(origin, redirectURL) else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}

enum FMDXAdministrationFailure: Error {
  case invalidProfile
  case missingPassword
  case loginFailed
  case notAnAdministrator
  case sessionUnavailable
  case setupUnavailable
  case unknown
}

struct FMDXAdministrationSessionPayload {
  let setupURL: URL
  let cookies: [HTTPCookie]
}

enum FMDXAdministration {
  static func canAdminister(_ profile: SDRConnectionProfile) -> Bool {
    profile.backend == .fmDxWebserver
  }

  static func setupURL(for profile: SDRConnectionProfile) throws -> URL {
    guard canAdminister(profile) else {
      throw FMDXAdministrationFailure.invalidProfile
    }
    return try makeHTTPURL(
      profile: profile,
      path: "\(pathWithTrailingSlash(profile.normalizedPath))setup"
    )
  }

  static func authenticate(
    profile: SDRConnectionProfile
  ) async throws -> FMDXAdministrationSessionPayload {
    guard canAdminister(profile) else {
      throw FMDXAdministrationFailure.invalidProfile
    }

    let password = profile.password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !password.isEmpty else {
      throw FMDXAdministrationFailure.missingPassword
    }

    let setupURL = try setupURL(for: profile)
    let loginURL: URL
    do {
      loginURL = try makeHTTPURL(
        profile: profile,
        path: "\(pathWithTrailingSlash(profile.normalizedPath))login"
      )
    } catch {
      throw FMDXAdministrationFailure.invalidProfile
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.httpShouldSetCookies = true
    configuration.httpCookieAcceptPolicy = .always
    let cookieStorage = HTTPCookieStorage()
    configuration.httpCookieStorage = cookieStorage
    let redirectDelegate = FMDXAdministrationRedirectDelegate(origin: loginURL)
    let session = URLSession(
      configuration: configuration,
      delegate: redirectDelegate,
      delegateQueue: nil
    )
    defer { session.invalidateAndCancel() }

    var loginCookies: [HTTPCookie] = []
    do {
      let loginRequest = try URLRequest.listenSDRFMDXLoginRequest(
        url: loginURL,
        password: password
      )
      let (_, response) = try await session.data(for: loginRequest)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        throw FMDXAdministrationFailure.loginFailed
      }

      // iOS nie zawsze przekazuje ciasteczko z odpowiedzi do kolejnego
      // żądania przy własnym, efemerycznym magazynie. Przechwyć je jawnie,
      // aby żądanie panelu korzystało z tej samej sesji co Android.
      loginCookies = responseCookies(from: httpResponse, for: loginURL)
      loginCookies.forEach(cookieStorage.setCookie)
    } catch let failure as FMDXAdministrationFailure {
      throw failure
    } catch {
      throw FMDXAdministrationFailure.loginFailed
    }

    let authenticationCookies = sessionCookies(
      from: loginCookies + (cookieStorage.cookies(for: setupURL) ?? [])
    )
    guard !authenticationCookies.isEmpty else {
      throw FMDXAdministrationFailure.sessionUnavailable
    }

    let setupHTML: String
    do {
      var request = URLRequest(url: setupURL)
      request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      request.setValue(
        "text/html,application/xhtml+xml",
        forHTTPHeaderField: "Accept"
      )
      request.setValue(
        ListenSDRNetworkIdentity.fmdxUserAgent(),
        forHTTPHeaderField: "User-Agent"
      )
      if let cookieHeader = cookieHeader(for: authenticationCookies) {
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
      }
      let (data, response) = try await session.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode),
        let html = String(data: data, encoding: .utf8)
      else {
        throw FMDXAdministrationFailure.setupUnavailable
      }
      setupHTML = html
    } catch let failure as FMDXAdministrationFailure {
      throw failure
    } catch {
      throw FMDXAdministrationFailure.setupUnavailable
    }

    guard isAdministrationPage(setupHTML) else {
      throw FMDXAdministrationFailure.notAnAdministrator
    }

    return FMDXAdministrationSessionPayload(
      setupURL: setupURL,
      cookies: authenticationCookies
    )
  }

  static func isAdministrationPage(_ html: String) -> Bool {
    let normalized = html.lowercased()
    return normalized.contains("setup.js")
      && (
        normalized.contains("password-adminpass")
          || normalized.contains("setup - fm-dx webserver")
      )
  }

  static func sessionCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
    var result: [HTTPCookie] = []
    for cookie in cookies where cookie.name == fmdxAdministrationSessionCookieName {
      guard !result.contains(where: {
        $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
      }) else {
        continue
      }
      result.append(cookie)
    }
    return result
  }

  static func responseCookies(
    from response: HTTPURLResponse,
    for url: URL
  ) -> [HTTPCookie] {
    let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
      guard
        let key = entry.key as? String,
        let value = entry.value as? String
      else {
        return
      }
      result[key] = value
    }
    return HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
  }

  static func cookieHeader(for cookies: [HTTPCookie]) -> String? {
    HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
  }

  private static func pathWithTrailingSlash(_ path: String) -> String {
    var output = path
    if !output.hasPrefix("/") {
      output = "/\(output)"
    }
    if !output.hasSuffix("/") {
      output.append("/")
    }
    return output
  }

  private static func makeHTTPURL(
    profile: SDRConnectionProfile,
    path: String
  ) throws -> URL {
    let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
      throw FMDXAdministrationFailure.invalidProfile
    }
    guard (1...65_535).contains(profile.port) else {
      throw FMDXAdministrationFailure.invalidProfile
    }

    var components = URLComponents()
    components.scheme = profile.useTLS ? "https" : "http"
    components.host = host
    components.port = profile.port
    components.path = path
    guard let url = components.url else {
      throw FMDXAdministrationFailure.invalidProfile
    }
    return url
  }
}

struct FMDXAdministrationWebView: UIViewRepresentable {
  let session: FMDXAdministrationSessionPayload

  func makeCoordinator() -> Coordinator {
    Coordinator(session: session)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsLinkPreview = false
    webView.accessibilityLabel = L10n.text(
      "fmdx.admin.webview",
      fallback: "FM-DX administration panel"
    )
    context.coordinator.loadSession(in: webView)
    return webView
  }

    func updateUIView(_ webView: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKNavigationDelegate {
    private let session: FMDXAdministrationSessionPayload
    private var didStartLoading = false

    init(session: FMDXAdministrationSessionPayload) {
      self.session = session
    }

    func loadSession(in webView: WKWebView) {
      guard !didStartLoading else { return }
      didStartLoading = true

      let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
      setCookie(at: 0, in: cookieStore, webView: webView)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard
        let targetURL = navigationAction.request.url,
        isSameFMDXOrigin(session.setupURL, targetURL)
      else {
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }

    private func setCookie(
      at index: Int,
      in cookieStore: WKHTTPCookieStore,
      webView: WKWebView
    ) {
      guard index < session.cookies.count else {
        webView.load(URLRequest(url: session.setupURL))
        return
      }

      cookieStore.setCookie(session.cookies[index]) { [weak self, weak webView] in
        guard let self, let webView else { return }
        DispatchQueue.main.async {
          self.setCookie(at: index + 1, in: cookieStore, webView: webView)
        }
      }
    }
  }
}

struct FMDXAdministrationView: View {
  let profile: SDRConnectionProfile

  @Environment(\.dismiss) private var dismiss
  @State private var administrationSession: FMDXAdministrationSessionPayload?
  @State private var failure: FMDXAdministrationFailure?
  @State private var isLoading = true
  @State private var retryAttempt = 0

  var body: some View {
    NavigationStack {
      Group {
        if let administrationSession {
          FMDXAdministrationWebView(session: administrationSession)
            .id(administrationSession.setupURL.absoluteString)
        } else if isLoading {
          loadingView
        } else if let failure {
          failureView(for: failure)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(
        L10n.text("fmdx.admin.title", fallback: "Server administration")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Close")) {
            dismiss()
          }
        }
      }
      .appScreenBackground()
    }
    .task(id: "\(profile.id.uuidString)-\(retryAttempt)") {
      await authenticate()
    }
  }

  private var loadingView: some View {
    VStack(spacing: 14) {
      ProgressView()
        .accessibilityLabel(
          L10n.text(
            "fmdx.admin.loading",
            fallback: "Loading administration panel"
          )
        )
      Text(
        L10n.text(
          "fmdx.admin.logging_in",
          fallback: "Logging in to the FM-DX administration panel..."
        )
      )
      .multilineTextAlignment(.center)
    }
    .padding(24)
  }

  private func failureView(for failure: FMDXAdministrationFailure) -> some View {
    VStack(spacing: 14) {
      Text(failureMessage(for: failure))
        .multilineTextAlignment(.center)
        .foregroundStyle(.red)

      Button(L10n.text("Try again", fallback: "Try again")) {
        retryAttempt += 1
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(24)
  }

  private func authenticate() async {
    administrationSession = nil
    failure = nil
    isLoading = true

    do {
      administrationSession = try await FMDXAdministration.authenticate(profile: profile)
    } catch let error as FMDXAdministrationFailure {
      failure = error
    } catch {
      failure = .unknown
    }
    isLoading = false
  }

  private func failureMessage(for failure: FMDXAdministrationFailure) -> String {
    switch failure {
    case .invalidProfile:
      return L10n.text(
        "fmdx.admin.invalid_profile",
        fallback: "This profile is not an FM-DX receiver."
      )
    case .missingPassword:
      return L10n.text(
        "fmdx.admin.missing_password",
        fallback: "Enter the FM-DX administrator password in the receiver profile first."
      )
    case .loginFailed:
      return L10n.text(
        "fmdx.admin.login_failed",
        fallback: "The FM-DX administrator login failed. Check the server address and password."
      )
    case .notAnAdministrator:
      return L10n.text(
        "fmdx.admin.not_administrator",
        fallback: "The saved password is valid, but it does not provide administrator access."
      )
    case .sessionUnavailable:
      return L10n.text(
        "fmdx.admin.session_unavailable",
        fallback: "The FM-DX server did not create an administration session."
      )
    case .setupUnavailable, .unknown:
      return L10n.text(
        "fmdx.admin.unavailable",
        fallback: "The administration panel could not be opened."
      )
    }
  }
}
