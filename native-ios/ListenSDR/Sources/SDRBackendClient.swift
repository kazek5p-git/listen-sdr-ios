import AVFAudio
import AudioToolbox
import Foundation
import ListenSDRCore
import UIKit

enum ListenSDRNetworkIdentity {
  static let clientName = "Listen SDR for iOS"
  static let userAgent = clientName
  static let openWebRXHandshake = "SERVER DE CLIENT client=\(clientName) type=receiver"

  static func fmdxUserAgent(
    platformToken: String = platformToken(),
    systemVersion: String = UIDevice.current.systemVersion
  ) -> String {
    let versionToken = systemVersion
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ".", with: "_")
    let safariVersion = systemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedVersionToken = versionToken.isEmpty ? "0_0" : versionToken
    let normalizedSafariVersion = safariVersion.isEmpty ? "0.0" : safariVersion
    return
      "Mozilla/5.0 (\(platformToken); CPU \(platformToken) OS \(normalizedVersionToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(normalizedSafariVersion) Mobile/15E148 \(clientName)"
  }

  static func kiwiIdentUser(username: String) -> String {
    let displayName = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? clientName
      : username
    return kiwiToken(displayName)
  }

  static func platformToken() -> String {
    switch UIDevice.current.userInterfaceIdiom {
    case .pad:
      return "iPad"
    case .phone:
      return "iPhone"
    default:
      return UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "iPhone"
        : UIDevice.current.model
    }
  }
}

extension URLRequest {
  mutating func applyListenSDRNetworkIdentity() {
    setValue(ListenSDRNetworkIdentity.userAgent, forHTTPHeaderField: "User-Agent")
  }

  static func listenSDRFMDXLoginRequest(
    url: URL,
    password: String,
    platformToken: String = ListenSDRNetworkIdentity.platformToken(),
    systemVersion: String = UIDevice.current.systemVersion
  ) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      ListenSDRNetworkIdentity.fmdxUserAgent(
        platformToken: platformToken,
        systemVersion: systemVersion
      ),
      forHTTPHeaderField: "User-Agent"
    )
    request.httpBody = try JSONSerialization.data(
      withJSONObject: ["password": password],
      options: []
    )
    return request
  }
}

enum BackendRuntimePolicy: Equatable {
  case interactive
  case passive
  case background

  var diagnosticsLabel: String {
    switch self {
    case .interactive:
      return "interactive"
    case .passive:
      return "passive"
    case .background:
      return "background"
    }
  }

  var allowsVisualTelemetry: Bool {
    self == .interactive
  }

  init(_ policy: BackendRuntimePolicyCore.Policy) {
    switch policy {
    case .interactive:
      self = .interactive
    case .passive:
      self = .passive
    case .background:
      self = .background
    }
  }

  var corePolicy: BackendRuntimePolicyCore.Policy {
    switch self {
    case .interactive:
      return .interactive
    case .passive:
      return .passive
    case .background:
      return .background
    }
  }
}

protocol SDRBackendClient {
  var backend: SDRBackend { get }
  func connect(profile: SDRConnectionProfile) async throws
  func disconnect() async
  func apply(settings: RadioSessionSettings) async throws
  func consumeServerError() async -> String?
  func consumeStatusUpdate() async -> String?
  func consumeTelemetryUpdate() async -> BackendTelemetryEvent?
  func sendControl(_ command: BackendControlCommand) async throws
  func isConnected() async -> Bool
  func setRuntimePolicy(_ policy: BackendRuntimePolicy) async
}

extension SDRBackendClient {
  func consumeStatusUpdate() async -> String? { nil }
  func consumeTelemetryUpdate() async -> BackendTelemetryEvent? { nil }
  func sendControl(_ command: BackendControlCommand) async throws {
    throw SDRClientError.unsupported("This backend does not support this control.")
  }
  func setRuntimePolicy(_ policy: BackendRuntimePolicy) async {}
}

enum SDRClientError: LocalizedError {
  case invalidHost
  case invalidPort
  case invalidURL
  case notConnected
  case unsupported(String)

  var errorDescription: String? {
    switch self {
    case .invalidHost:
      return "Host is empty."
    case .invalidPort:
      return "Port must be in range 1-65535."
    case .invalidURL:
      return "Unable to build WebSocket URL."
    case .notConnected:
      return "Not connected."
    case .unsupported(let message):
      return message
    }
  }
}

private func validate(profile: SDRConnectionProfile) throws -> (host: String, port: Int) {
  let host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !host.isEmpty else { throw SDRClientError.invalidHost }
  guard (1...65535).contains(profile.port) else { throw SDRClientError.invalidPort }
  return (host, profile.port)
}

private func pathWithTrailingSlash(_ path: String) -> String {
  var output = path
  if !output.hasPrefix("/") {
    output = "/\(output)"
  }
  if !output.hasSuffix("/") {
    output.append("/")
  }
  return output
}

private func makeWebSocketURL(profile: SDRConnectionProfile, path: String) throws -> URL {
  let endpoint = try validate(profile: profile)
  var components = URLComponents()
  components.scheme = profile.useTLS ? "wss" : "ws"
  components.host = endpoint.host
  components.port = endpoint.port
  components.path = path

  guard let url = components.url else {
    throw SDRClientError.invalidURL
  }
  return url
}

private func makeHTTPURL(profile: SDRConnectionProfile, path: String) throws -> URL {
  let endpoint = try validate(profile: profile)
  var components = URLComponents()
  components.scheme = profile.useTLS ? "https" : "http"
  components.host = endpoint.host
  components.port = endpoint.port
  components.path = path

  guard let url = components.url else {
    throw SDRClientError.invalidURL
  }
  return url
}

private final class HTTPRedirectCaptureDelegate: NSObject, URLSessionTaskDelegate {
  private(set) var redirectURL: URL?

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    redirectURL = request.url
    completionHandler(nil)
  }
}

private func websocketURL(fromHTTPRedirect url: URL) -> URL? {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
    return nil
  }

  switch components.scheme?.lowercased() {
  case "http":
    components.scheme = "ws"
  case "https":
    components.scheme = "wss"
  case "ws", "wss":
    break
  default:
    return nil
  }

  return components.url
}

private func encodeJSONString(_ payload: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: payload, options: [])
  guard let text = String(data: data, encoding: .utf8) else {
    throw SDRClientError.unsupported("Unable to encode JSON payload.")
  }
  return text
}

private func kiwiMode(from mode: DemodulationMode) -> String {
  mode.kiwiProtocolMode
}

private func openWebRXMode(from mode: DemodulationMode) -> String {
  mode.openWebRXProtocolMode
}

private func openWebRXBandpass(for mode: DemodulationMode) -> ReceiverBandpass {
  mode.openWebRXDefaultBandpass
}

private func kiwiToken(_ raw: String) -> String {
  raw
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: " ", with: "%20")
}

private func kiwiAuthenticationErrorDescription(code: String) -> String {
  switch code {
  case "1":
    return "Bad password or all channels that do not require a password are busy."
  case "2":
    return "Receiver is still determining local interface address."
  case "3":
    return "Admin connection is not allowed from this IP address."
  case "4":
    return "No admin password set. Admin access is local network only."
  case "5":
    return "Multiple connections from the same IP are not allowed."
  case "6":
    return "Receiver database update in progress. Try again in about a minute."
  case "7":
    return "Another admin connection is already open."
  default:
    return "Authentication rejected by KiwiSDR."
  }
}

private actor KiwiWaterfallAvailabilityStore {
  static let shared = KiwiWaterfallAvailabilityStore()

  private let defaults = UserDefaults.standard
  private let defaultsKey = "ListenSDR.kiwiBlockedWaterfallEndpoints.v1"
  private var blockedEndpointReasons: [String: String]

  init() {
    blockedEndpointReasons = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
  }

  func blockedReason(for endpointKey: String) -> String? {
    blockedEndpointReasons[endpointKey]
  }

  func rememberBlocked(endpointKey: String, reason: String) {
    blockedEndpointReasons[endpointKey] = reason
    defaults.set(blockedEndpointReasons, forKey: defaultsKey)
  }
}

private func demodulationModeFromKiwi(_ rawValue: String?) -> DemodulationMode? {
  DemodulationMode.fromKiwi(rawValue)
}

actor KiwiSDRClient: SDRBackendClient {
  private enum StreamKind {
    case sound
    case waterfall
  }

  let backend: SDRBackend = .kiwiSDR

  private var sndSocket: URLSessionWebSocketTask?
  private var wfSocket: URLSessionWebSocketTask?
  private var sndReceiveTask: Task<Void, Never>?
  private var wfReceiveTask: Task<Void, Never>?
  private var sndKeepAliveTask: Task<Void, Never>?
  private var wfKeepAliveTask: Task<Void, Never>?

  private var lastServerMessage: String?
  private var pendingStatusUpdate: String?
  private var adpcmDecoder = KiwiIMAADPCMDecoder()
  private var sampleRateHz = 12_000

  private var telemetryQueue: [BackendTelemetryEvent] = []
  private var latestRSSI: Double?
  private var latestWaterfallBins: [UInt8] = []
  private var latestWaterfallFFTSize: Int?
  private var lastTelemetryAt: Date = .distantPast
  private var latestTelemetry: KiwiTelemetry?
  private var latestTunedFrequencyHz: Int?
  private var latestTunedMode: DemodulationMode?
  private var latestBandName: String?
  private var latestPassband: ReceiverBandpass?
  private var kiwiBandwidthHz: Int?
  private var kiwiZoomMax: Int?
  private var receivedAudioFrameCount = 0
  private var audioWatchdogTask: Task<Void, Never>?
  private var lastReportedTunedFrequencyHz: Int?
  private var lastReportedTunedMode: DemodulationMode?
  private var lastReportedBandName: String?
  private var lastReportedPassband: ReceiverBandpass?
  private var activeProfile: SDRConnectionProfile?
  private var activeBasePath = "/"
  private var lastAppliedSettings: RadioSessionSettings?
  private var runtimePolicy: BackendRuntimePolicy = .interactive
  private var kiwiEndpointKey: String?
  private var firstAudioFrameAt: Date?
  private var pendingWaterfallActivationTask: Task<Void, Never>?

  private let kiwiStableAudioFrameThreshold = 3
  private let kiwiStableAudioWaterfallDelaySeconds: TimeInterval = 2.5

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    activeProfile = profile
    activeBasePath = basePath

    let sndURL = try makeWebSocketURL(
      profile: profile,
      path: "\(basePath)\(Int(Date().timeIntervalSince1970))/SND"
    )
    let endpointKey = makeKiwiEndpointKey(for: sndURL, basePath: basePath)
    kiwiEndpointKey = endpointKey
    let blockedWaterfallReason = await KiwiWaterfallAvailabilityStore.shared.blockedReason(for: endpointKey)
    log("Connecting audio stream: \(sndURL.absoluteString)")
    var soundRequest = URLRequest(url: sndURL)
    soundRequest.applyListenSDRNetworkIdentity()
    let soundTask = URLSession.shared.webSocketTask(with: soundRequest)
    sndSocket = soundTask
    soundTask.resume()
    sndReceiveTask = Task { [soundTask] in
      await self.receiveLoop(task: soundTask, stream: .sound)
    }
    sndKeepAliveTask = Task { [soundTask] in
      await self.keepAliveLoop(task: soundTask)
    }
    audioWatchdogTask = Task {
      try? await Task.sleep(nanoseconds: 6_000_000_000)
      self.logMissingAudioIfNeeded()
    }

    try await sendSND("SET auth t=kiwi p=\(kiwiToken(profile.password))")
    try await sendSND("SET ident_user=\(ListenSDRNetworkIdentity.kiwiIdentUser(username: profile.username))")
    try await sendSND("SET compression=0")
    try await sendSND("SET keepalive")

    if runtimePolicy.allowsVisualTelemetry, blockedWaterfallReason == nil {
      log(
        "Deferring Kiwi waterfall stream until audio is stable (\(kiwiStableAudioFrameThreshold)+ frames, \(String(format: "%.1f", kiwiStableAudioWaterfallDelaySeconds)) s)."
      )
    } else if let blockedWaterfallReason {
      log("Skipping Kiwi waterfall stream for \(endpointKey): \(blockedWaterfallReason)", severity: .warning)
    }

    log("Connection initialized")
  }

  func disconnect() async {
    sndReceiveTask?.cancel()
    sndReceiveTask = nil

    sndKeepAliveTask?.cancel()
    sndKeepAliveTask = nil
    audioWatchdogTask?.cancel()
    audioWatchdogTask = nil
    pendingWaterfallActivationTask?.cancel()
    pendingWaterfallActivationTask = nil

    sndSocket?.cancel(with: .normalClosure, reason: nil)
    sndSocket = nil
    closeWaterfallStream(clearTelemetry: false)

    lastServerMessage = nil
    pendingStatusUpdate = nil
    sampleRateHz = 12_000
    adpcmDecoder.reset()
    latestRSSI = nil
    latestWaterfallBins = []
    latestWaterfallFFTSize = nil
    telemetryQueue.removeAll()
    lastTelemetryAt = .distantPast
    latestTelemetry = nil
    latestTunedFrequencyHz = nil
    latestTunedMode = nil
    latestBandName = nil
    latestPassband = nil
    kiwiBandwidthHz = nil
    kiwiZoomMax = nil
    receivedAudioFrameCount = 0
    firstAudioFrameAt = nil
    lastReportedTunedFrequencyHz = nil
    lastReportedTunedMode = nil
    lastReportedBandName = nil
    lastReportedPassband = nil
    activeProfile = nil
    activeBasePath = "/"
    lastAppliedSettings = nil
    kiwiEndpointKey = nil

    await MainActor.run {
      SharedAudioOutput.engine.stop()
    }
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard sndSocket != nil else { throw SDRClientError.notConnected }
    lastAppliedSettings = settings

    let mode = kiwiMode(from: settings.mode)
    let passband = settings.kiwiPassband(for: settings.mode, sampleRateHz: sampleRateHz)
    let frequencyKHz = Double(settings.frequencyHz) / 1000.0
    let formattedFrequency = String(format: "%.3f", frequencyKHz)

    try await sendSND(
      "SET mod=\(mode) low_cut=\(passband.lowCut) high_cut=\(passband.highCut) freq=\(formattedFrequency)"
    )
    try? await applyKiwiWaterfallSettings(settings)
    log("Applied tuning: mode=\(mode) freq=\(formattedFrequency) kHz")

    if settings.agcEnabled {
      try await sendSND("SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50")
    } else {
      let manualGain = Int(settings.rfGain.rounded())
      try await sendSND("SET agc=0 hang=0 thresh=-100 slope=6 decay=1000 manGain=\(manualGain)")
    }

      let squelch = SquelchRuntimeControl.kiwiCommand(
        enabled: settings.squelchEnabled,
        threshold: RadioSessionSettings.clampedKiwiSquelchThreshold(settings.kiwiSquelchThreshold)
      )
      try await sendSND("SET squelch=\(squelch.enabledFlag) max=\(squelch.max)")
      try await sendKiwiNoiseBlanker(settings: settings)
      try await sendKiwiNoiseFilter(settings: settings)
    }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func consumeStatusUpdate() async -> String? {
    defer { pendingStatusUpdate = nil }
    return pendingStatusUpdate
  }

  func consumeTelemetryUpdate() async -> BackendTelemetryEvent? {
    guard !telemetryQueue.isEmpty else { return nil }
    return telemetryQueue.removeFirst()
  }

  func setRuntimePolicy(_ policy: BackendRuntimePolicy) async {
    guard runtimePolicy != policy else { return }
    let previousPolicy = runtimePolicy
    runtimePolicy = policy
    log("Runtime policy changed: \(previousPolicy.diagnosticsLabel) -> \(policy.diagnosticsLabel)")

    guard let activeProfile else { return }
    if policy.allowsVisualTelemetry {
      guard wfSocket == nil else { return }
      if await blockedWaterfallReason() != nil { return }
      await scheduleWaterfallActivationIfNeeded(reason: "runtime policy \(policy.diagnosticsLabel)")
    } else {
      pendingWaterfallActivationTask?.cancel()
      pendingWaterfallActivationTask = nil
      log("Closing Kiwi waterfall stream for runtime policy \(policy.diagnosticsLabel).")
      closeWaterfallStream(clearTelemetry: true)
    }
  }

  func sendControl(_ command: BackendControlCommand) async throws {
    switch command {
    case .setKiwiWaterfall(
      let speed,
      let zoom,
      let minDB,
      let maxDB,
      let centerFrequencyHz,
      let panOffsetBins,
      let windowFunction,
      let interpolation,
      let cicCompensation
    ):
      guard wfSocket != nil else { return }
      if await blockedWaterfallReason() != nil { return }
      let safeSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(speed)
      let safeZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(zoom)
      let safeMinDB = RadioSessionSettings.clampedKiwiWaterfallMinDB(minDB)
      var safeMaxDB = RadioSessionSettings.clampedKiwiWaterfallMaxDB(maxDB)
      let safeWindowFunction = RadioSessionSettings.normalizedKiwiWaterfallWindowFunction(windowFunction)
      let safeInterpolation = RadioSessionSettings.normalizedKiwiWaterfallInterpolation(interpolation)
      if safeMaxDB <= safeMinDB {
        safeMaxDB = min(0, safeMinDB + 10)
      }
      var snapshot = lastAppliedSettings ?? .default
      snapshot.kiwiWaterfallSpeed = safeSpeed
      snapshot.kiwiWaterfallZoom = safeZoom
      snapshot.kiwiWaterfallMinDB = safeMinDB
      snapshot.kiwiWaterfallMaxDB = safeMaxDB
      snapshot.frequencyHz = centerFrequencyHz
      snapshot.kiwiWaterfallPanOffsetBins = panOffsetBins
      snapshot.kiwiWaterfallWindowFunction = safeWindowFunction
      snapshot.kiwiWaterfallInterpolation = safeInterpolation
      snapshot.kiwiWaterfallCICCompensation = cicCompensation
      lastAppliedSettings = snapshot
      try await sendWF("SET wf_speed=\(safeSpeed)")
      try await sendWF("SET maxdb=\(safeMaxDB) mindb=\(safeMinDB)")
      if let viewportStartBin = kiwiWaterfallStartBin(
        frequencyHz: centerFrequencyHz,
        zoom: safeZoom,
        panOffsetBins: panOffsetBins
      ) {
        let safeViewportZoom = min(safeZoom, kiwiZoomMax ?? safeZoom)
        try await sendWF("SET zoom=\(safeViewportZoom) start=\(viewportStartBin)")
      }
      try await sendWF("SET window_func=\(safeWindowFunction)")
      try await sendWF("SET interp=\(safeInterpolation + (cicCompensation ? 10 : 0))")
      log(
        "Kiwi waterfall updated: speed=\(safeSpeed), zoom=\(safeZoom), db=\(safeMinDB)...\(safeMaxDB), win=\(safeWindowFunction), interp=\(safeInterpolation), cic=\(cicCompensation ? 1 : 0), pan=\(panOffsetBins)"
      )

      case .setKiwiPassband(let lowCut, let highCut, let frequencyHz, let mode):
        let normalizedBandpass = RadioSessionSettings.normalizedKiwiBandpass(
          ReceiverBandpass(lowCut: lowCut, highCut: highCut),
          mode: mode,
        sampleRateHz: sampleRateHz
      )
      var snapshot = lastAppliedSettings ?? .default
      snapshot.mode = mode
      snapshot.frequencyHz = frequencyHz
      snapshot.setKiwiPassband(normalizedBandpass, for: mode, sampleRateHz: sampleRateHz)
      lastAppliedSettings = snapshot
      let frequencyKHz = Double(frequencyHz) / 1000.0
      let formattedFrequency = String(format: "%.3f", frequencyKHz)
      try await sendSND(
        "SET mod=\(mode.kiwiProtocolMode) low_cut=\(normalizedBandpass.lowCut) high_cut=\(normalizedBandpass.highCut) freq=\(formattedFrequency)"
      )
        latestPassband = normalizedBandpass
        emitKiwiTelemetry(force: true)
        emitKiwiTuning()
        log("Kiwi passband updated: \(normalizedBandpass.lowCut)...\(normalizedBandpass.highCut) Hz")

      case .setKiwiNoiseBlanker(
        let algorithm,
        let gate,
        let threshold,
        let wildThreshold,
        let wildTaps,
        let wildImpulseSamples
      ):
        var snapshot = lastAppliedSettings ?? .default
        snapshot.kiwiNoiseBlankerAlgorithm = algorithm
        snapshot.kiwiNoiseBlankerGate = gate
        snapshot.kiwiNoiseBlankerThreshold = threshold
        snapshot.kiwiNoiseBlankerWildThreshold = wildThreshold
        snapshot.kiwiNoiseBlankerWildTaps = wildTaps
        snapshot.kiwiNoiseBlankerWildImpulseSamples = wildImpulseSamples
        lastAppliedSettings = snapshot
        try await sendKiwiNoiseBlanker(
          algorithm: algorithm,
          gate: gate,
          threshold: threshold,
          wildThreshold: wildThreshold,
          wildTaps: wildTaps,
          wildImpulseSamples: wildImpulseSamples
        )
        log("Kiwi noise blanker updated: algo=\(algorithm.rawValue)")

      case .setKiwiNoiseFilter(let algorithm, let denoiseEnabled, let autonotchEnabled):
        var snapshot = lastAppliedSettings ?? .default
        snapshot.kiwiNoiseFilterAlgorithm = algorithm
        snapshot.kiwiDenoiseEnabled = denoiseEnabled
        snapshot.kiwiAutonotchEnabled = autonotchEnabled
        lastAppliedSettings = snapshot
        try await sendKiwiNoiseFilter(
          algorithm: algorithm,
          denoiseEnabled: denoiseEnabled,
          autonotchEnabled: autonotchEnabled
        )
        log(
          "Kiwi noise filter updated: algo=\(algorithm.rawValue), denoise=\(denoiseEnabled ? 1 : 0), autonotch=\(autonotchEnabled ? 1 : 0)"
        )

      case .setKiwiSquelch(let enabled, let threshold):
        var snapshot = lastAppliedSettings ?? .default
        snapshot.squelchEnabled = enabled
        snapshot.kiwiSquelchThreshold = RadioSessionSettings.clampedKiwiSquelchThreshold(threshold)
        lastAppliedSettings = snapshot
        let squelch = SquelchRuntimeControl.kiwiCommand(
          enabled: snapshot.squelchEnabled,
          threshold: snapshot.kiwiSquelchThreshold
        )
        try await sendSND("SET squelch=\(squelch.enabledFlag) max=\(squelch.max)")
        log("Kiwi squelch updated: enabled=\(snapshot.squelchEnabled) threshold=\(snapshot.kiwiSquelchThreshold)")

      default:
        throw SDRClientError.unsupported("KiwiSDR does not support this control.")
      }
    }

  private func sendKiwiNoiseBlanker(settings: RadioSessionSettings) async throws {
    try await sendKiwiNoiseBlanker(
      algorithm: settings.kiwiNoiseBlankerAlgorithm,
      gate: settings.kiwiNoiseBlankerGate,
      threshold: settings.kiwiNoiseBlankerThreshold,
      wildThreshold: settings.kiwiNoiseBlankerWildThreshold,
      wildTaps: settings.kiwiNoiseBlankerWildTaps,
      wildImpulseSamples: settings.kiwiNoiseBlankerWildImpulseSamples
    )
  }

  private func sendKiwiNoiseBlanker(
    algorithm: KiwiNoiseBlankerAlgorithm,
    gate: Int,
    threshold: Int,
    wildThreshold: Double,
    wildTaps: Int,
    wildImpulseSamples: Int
  ) async throws {
    try await sendSND("SET nb algo=\(algorithm.rawValue)")

    switch algorithm {
    case .off:
      break

    case .standard:
      try await sendSND("SET nb type=0 param=0 pval=\(RadioSessionSettings.clampedKiwiNoiseBlankerGate(gate))")
      try await sendSND("SET nb type=0 param=1 pval=\(RadioSessionSettings.clampedKiwiNoiseBlankerThreshold(threshold))")

    case .wild:
      let normalizedThreshold = RadioSessionSettings.clampedKiwiNoiseBlankerWildThreshold(wildThreshold)
      let normalizedTaps = RadioSessionSettings.clampedKiwiNoiseBlankerWildTaps(wildTaps)
      let normalizedImpulseSamples = RadioSessionSettings.clampedKiwiNoiseBlankerWildImpulseSamples(wildImpulseSamples)
      try await sendSND("SET nb type=0 param=0 pval=\(String(format: "%.2f", normalizedThreshold))")
      try await sendSND("SET nb type=0 param=1 pval=\(normalizedTaps)")
      try await sendSND("SET nb type=0 param=2 pval=\(normalizedImpulseSamples)")
    }

    try await sendSND("SET nb type=0 en=\(algorithm == .off ? 0 : 1)")
  }

  private func sendKiwiNoiseFilter(settings: RadioSessionSettings) async throws {
    try await sendKiwiNoiseFilter(
      algorithm: settings.kiwiNoiseFilterAlgorithm,
      denoiseEnabled: settings.kiwiDenoiseEnabled,
      autonotchEnabled: settings.kiwiAutonotchEnabled
    )
  }

  private func sendKiwiNoiseFilter(
    algorithm: KiwiNoiseFilterAlgorithm,
    denoiseEnabled: Bool,
    autonotchEnabled: Bool
  ) async throws {
    try await sendSND("SET nr algo=\(algorithm.rawValue)")

    if algorithm == .off {
      try await sendSND("SET nr type=0 en=0")
      try await sendSND("SET nr type=1 en=0")
      return
    }

    let noiseFilterDenoiseEnabled = algorithm == .spectral ? true : denoiseEnabled
    let noiseFilterAutonotchEnabled = algorithm == .spectral ? false : autonotchEnabled

    switch algorithm {
    case .off:
      break

    case .wdsp:
      let p2 = 8.192e-2 / pow(2.0, Double(20 - 10))
      let p3 = 8192.0 / pow(2.0, Double(23 - 7))
      try await sendSND("SET nr type=0 param=0 pval=64")
      try await sendSND("SET nr type=0 param=1 pval=16")
      try await sendSND("SET nr type=0 param=2 pval=\(p2)")
      try await sendSND("SET nr type=0 param=3 pval=\(p3)")
      try await sendSND("SET nr type=1 param=0 pval=64")
      try await sendSND("SET nr type=1 param=1 pval=16")
      try await sendSND("SET nr type=1 param=2 pval=\(p2)")
      try await sendSND("SET nr type=1 param=3 pval=\(p3)")

    case .original:
      try await sendSND("SET nr type=0 param=0 pval=1")
      try await sendSND("SET nr type=0 param=1 pval=0.05")
      try await sendSND("SET nr type=0 param=2 pval=0.98")
      try await sendSND("SET nr type=0 param=3 pval=0")
      try await sendSND("SET nr type=1 param=0 pval=48")
      try await sendSND("SET nr type=1 param=1 pval=0.125")
      try await sendSND("SET nr type=1 param=2 pval=0.99915")
      try await sendSND("SET nr type=1 param=3 pval=0")

    case .spectral:
      try await sendSND("SET nr type=0 param=0 pval=1.0")
      try await sendSND("SET nr type=0 param=1 pval=0.95")
      try await sendSND("SET nr type=0 param=2 pval=1000.0")
      try await sendSND("SET nr type=0 param=3 pval=0")
    }

    try await sendSND("SET nr type=0 en=\(noiseFilterDenoiseEnabled ? 1 : 0)")
    if algorithm == .spectral {
      try await sendSND("SET nr type=1 en=0")
    } else {
      try await sendSND("SET nr type=1 en=\(noiseFilterAutonotchEnabled ? 1 : 0)")
    }
  }

  private func applyKiwiWaterfallSettings(_ settings: RadioSessionSettings) async throws {
    let wfSpeed = RadioSessionSettings.normalizedKiwiWaterfallSpeed(settings.kiwiWaterfallSpeed)
    let wfZoom = RadioSessionSettings.clampedKiwiWaterfallZoom(settings.kiwiWaterfallZoom)
    let wfMinDB = RadioSessionSettings.clampedKiwiWaterfallMinDB(settings.kiwiWaterfallMinDB)
    var wfMaxDB = RadioSessionSettings.clampedKiwiWaterfallMaxDB(settings.kiwiWaterfallMaxDB)
    let wfWindowFunction = RadioSessionSettings.normalizedKiwiWaterfallWindowFunction(
      settings.kiwiWaterfallWindowFunction
    )
    let wfInterpolation = RadioSessionSettings.normalizedKiwiWaterfallInterpolation(
      settings.kiwiWaterfallInterpolation
    )
    if wfMaxDB <= wfMinDB {
      wfMaxDB = min(0, wfMinDB + 10)
    }

    try await sendWF("SET wf_speed=\(wfSpeed)")
    try await sendWF("SET maxdb=\(wfMaxDB) mindb=\(wfMinDB)")
    if let viewportStartBin = kiwiWaterfallStartBin(
      frequencyHz: settings.frequencyHz,
      zoom: wfZoom,
      panOffsetBins: settings.kiwiWaterfallPanOffsetBins
    ) {
      let safeViewportZoom = min(wfZoom, kiwiZoomMax ?? wfZoom)
      try await sendWF("SET zoom=\(safeViewportZoom) start=\(viewportStartBin)")
    }
    try await sendWF("SET window_func=\(wfWindowFunction)")
    try await sendWF("SET interp=\(wfInterpolation + (settings.kiwiWaterfallCICCompensation ? 10 : 0))")
  }

  private func openWaterfallStream(profile: SDRConnectionProfile, basePath: String) async throws {
    closeWaterfallStream(clearTelemetry: false)

    let timestamp = Int(Date().timeIntervalSince1970)
    let wfURL = try makeWebSocketURL(profile: profile, path: "\(basePath)\(timestamp)/W/F")
    log("Connecting waterfall stream: \(wfURL.absoluteString)")
    var waterfallRequest = URLRequest(url: wfURL)
    waterfallRequest.applyListenSDRNetworkIdentity()
    let waterfallTask = URLSession.shared.webSocketTask(with: waterfallRequest)
    wfSocket = waterfallTask
    waterfallTask.resume()
    wfReceiveTask = Task { [waterfallTask] in
      await self.receiveLoop(task: waterfallTask, stream: .waterfall)
    }
    wfKeepAliveTask = Task { [waterfallTask] in
      await self.keepAliveLoop(task: waterfallTask)
    }

    try await sendWF("SET auth t=kiwi p=\(kiwiToken(profile.password))")
    try await sendWF("SET wf_comp=0")
    try await sendWF("SET wf_speed=2")
    try await sendWF("SET maxdb=-20 mindb=-145")
    try await sendWF("SET zoom=0 start=0")
    try await sendWF("SET keepalive")
  }

  private func closeWaterfallStream(clearTelemetry: Bool) {
    wfReceiveTask?.cancel()
    wfReceiveTask = nil
    wfKeepAliveTask?.cancel()
    wfKeepAliveTask = nil
    wfSocket?.cancel(with: .normalClosure, reason: nil)
    wfSocket = nil

    guard clearTelemetry else { return }
    latestWaterfallBins = []
    latestWaterfallFFTSize = nil
    emitKiwiTelemetry(force: true)
  }

  func isConnected() async -> Bool {
    sndSocket != nil
  }

  private func sendSND(_ message: String) async throws {
    guard let sndSocket else { throw SDRClientError.notConnected }
    try await sndSocket.send(.string(message))
  }

  private func sendWF(_ message: String) async throws {
    guard let wfSocket else { throw SDRClientError.notConnected }
    try await wfSocket.send(.string(message))
  }

  private func receiveLoop(task: URLSessionWebSocketTask, stream: StreamKind) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text, stream: stream)
        case .data(let data):
          await handleInboundData(data, stream: stream)
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error, stream: stream)
        break
      }
    }
  }

  private func keepAliveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      // A slower keepalive cadence is enough to keep the socket warm and saves background wakeups.
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      if Task.isCancelled {
        return
      }

      do {
        try await task.send(.string("SET keepalive"))
      } catch {
        return
      }
    }
  }

  private func handleInboundText(_ text: String, stream: StreamKind) async {
    if text.contains("badp=") || text.contains("too_busy=") || text.contains("down=") {
      await handleKiwiMessage(text, stream: stream)
      return
    }

    guard stream == .sound else {
      return
    }
  }

  private func handleInboundData(_ data: Data, stream: StreamKind) async {
    guard data.count >= 4 else { return }
    let tag = String(decoding: data.prefix(3), as: UTF8.self)
    let body = Data(data.dropFirst(3))

    switch tag {
    case "MSG":
      let payload = Data(body.dropFirst())
      guard let text = String(data: payload, encoding: .utf8) else { return }
      await handleKiwiMessage(text, stream: stream)

    case "SND":
      await handleKiwiAudio(body)

    case "W/F":
      await handleKiwiWaterfall(body)

    default:
      if stream == .sound {
        log("Unknown sound tag: \(tag)", severity: .warning)
      }
    }
  }

  private func handleKiwiMessage(_ payload: String, stream: StreamKind) async {
    let entries = payload.split(separator: " ")
    var tuningChanged = false
    var pendingLowCut: Int?
    var pendingHighCut: Int?

    for entry in entries {
      let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = String(parts[0])
      let value = parts.count > 1 ? String(parts[1]) : nil

      switch name {
      case "audio_rate":
        if let value, let inputRate = Int(value) {
          try? await sendSND("SET AR OK in=\(inputRate) out=44100")
        }

      case "sample_rate":
        if let value, let sampleRate = Double(value) {
          sampleRateHz = max(8000, Int(sampleRate.rounded()))
          emitKiwiTelemetry(force: true)
        }

      case "bandwidth":
        if let value, let bandwidth = Int(value), bandwidth > 0 {
          kiwiBandwidthHz = bandwidth
          emitKiwiTelemetry(force: true)
        }

      case "zoom_max":
        if let value, let zoomMax = Int(value), zoomMax >= 0 {
          kiwiZoomMax = zoomMax
          emitKiwiTelemetry(force: true)
        }

      case "freq":
        if let value, let parsedFrequencyHz = parseKiwiFrequencyHz(value) {
          latestTunedFrequencyHz = parsedFrequencyHz
          tuningChanged = true
        }

      case "mod", "mode":
        if let mode = demodulationModeFromKiwi(value) {
          latestTunedMode = mode
          tuningChanged = true
        }

      case "band":
        if let value {
          let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
          latestBandName = normalized.isEmpty ? nil : normalized
          tuningChanged = true
        }

      case "low_cut":
        if let value, let parsedValue = parseKiwiPassbandCut(value) {
          pendingLowCut = parsedValue
        }

      case "high_cut":
        if let value, let parsedValue = parseKiwiPassbandCut(value) {
          pendingHighCut = parsedValue
        }

      case "load_cfg":
        if let value {
          let decodedValue = value.removingPercentEncoding ?? value
          applyKiwiConfigPayload(decodedValue, tuningChanged: &tuningChanged)
        }

      case "badp":
        if value == "0" {
          break
        }

        let message: String
        if let value {
          message = kiwiAuthenticationErrorDescription(code: value)
        } else {
          message = "Authentication rejected by KiwiSDR."
        }

        if stream == .sound {
          lastServerMessage = message
          log(message, severity: .error)
        } else {
          if shouldDisableWaterfall(for: message) {
            await disableWaterfallForCurrentEndpoint(reason: message)
          }
          log("Waterfall stream authentication failed: \(message)", severity: .warning)
        }

      case "too_busy":
        let message = "KiwiSDR is currently busy (all client slots are used)."
        if stream == .sound {
          lastServerMessage = message
        } else {
          await disableWaterfallForCurrentEndpoint(reason: message)
        }
        log(message, severity: .warning)

      case "down":
        let message = "KiwiSDR reports that the receiver is down."
        if stream == .sound {
          lastServerMessage = message
        } else {
          pendingStatusUpdate = message
        }
        log(message, severity: .warning)

      default:
        break
      }
    }

    if pendingLowCut != nil || pendingHighCut != nil {
      let currentMode = latestTunedMode ?? .am
      let currentPassband = latestPassband ?? RadioSessionSettings.default.kiwiPassband(for: currentMode, sampleRateHz: sampleRateHz)
      let mergedPassband = RadioSessionSettings.normalizedKiwiBandpass(
        ReceiverBandpass(
          lowCut: pendingLowCut ?? currentPassband.lowCut,
          highCut: pendingHighCut ?? currentPassband.highCut
        ),
        mode: currentMode,
        sampleRateHz: sampleRateHz
      )
      if latestPassband != mergedPassband {
        latestPassband = mergedPassband
        tuningChanged = true
      }
    }

    if tuningChanged {
      emitKiwiTuning()
    }
  }

  private func handleKiwiAudio(_ body: Data) async {
    guard body.count > 7 else { return }

    let flags = body[0]
    let isStereo = (flags & 0x08) != 0
    let isCompressed = (flags & 0x10) != 0
    let isLittleEndian = (flags & 0x80) != 0

    let smeter = (Int(body[5]) << 8) | Int(body[6])
    latestRSSI = (0.1 * Double(smeter)) - 127.0
    emitKiwiTelemetry(force: false)

    let audioBytes = Data(body.dropFirst(7))
    guard !audioBytes.isEmpty else { return }

    let decodedPCM: [Int16]
    if isCompressed {
      decodedPCM = adpcmDecoder.decode(audioBytes)
    } else {
      decodedPCM = decodeInt16PCM(audioBytes, littleEndian: isLittleEndian)
    }

    let pcm = isStereo ? downmixInterleavedStereoPCM(decodedPCM) : decodedPCM

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }
    receivedAudioFrameCount += 1
    if receivedAudioFrameCount == 1 {
      firstAudioFrameAt = Date()
    }
    audioWatchdogTask?.cancel()
    audioWatchdogTask = nil
    if receivedAudioFrameCount <= 3 {
      let rms = sqrt(floats.reduce(0) { $0 + ($1 * $1) } / Float(max(floats.count, 1)))
      log(
        String(
          format: "Audio frame #%d received (flags=0x%02X, rate=%d Hz, rms=%.4f, compressed=%d, stereo=%d)",
          receivedAudioFrameCount,
          Int(flags),
          sampleRateHz,
          rms,
          isCompressed ? 1 : 0,
          isStereo ? 1 : 0
        )
      )
    }
    if runtimePolicy.allowsVisualTelemetry, wfSocket == nil {
      await scheduleWaterfallActivationIfNeeded(reason: "audio stabilized")
    }

    let sampleRate = Double(sampleRateHz)
    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func logMissingAudioIfNeeded() {
    guard sndSocket != nil else { return }
    guard receivedAudioFrameCount == 0 else { return }
    pendingStatusUpdate = NSLocalizedString(
      "Connected, but Kiwi is not sending audio.",
      comment: "Status shown when KiwiSDR is connected but audio frames are missing"
    )
    log("Connected, but no Kiwi audio frames were received within 6 seconds.", severity: .warning)
  }

  private func handleKiwiWaterfall(_ body: Data) async {
    var payload = body
    guard !payload.isEmpty else { return }
    payload.removeFirst() // protocol header byte used by Kiwi W/F stream
    guard payload.count > 12 else { return }

    let bins = Array(payload.dropFirst(12))
    guard !bins.isEmpty else { return }

    latestWaterfallFFTSize = bins.count
    latestWaterfallBins = downsampleBins(bins, targetCount: 320)
    emitKiwiTelemetry(force: false)
  }

  private func downsampleBins(_ bins: [UInt8], targetCount: Int) -> [UInt8] {
    guard bins.count > targetCount, targetCount > 1 else {
      return bins
    }

    var output: [UInt8] = []
    output.reserveCapacity(targetCount)
    let stride = Double(bins.count - 1) / Double(targetCount - 1)

    for index in 0..<targetCount {
      let sourceIndex = Int((Double(index) * stride).rounded())
      output.append(bins[min(max(sourceIndex, 0), bins.count - 1)])
    }
    return output
  }

  private func emitKiwiTelemetry(force: Bool) {
    let now = Date()
    if !force, now.timeIntervalSince(lastTelemetryAt) < 0.5 {
      return
    }
    lastTelemetryAt = now

    let telemetry = KiwiTelemetry(
      rssiDBm: latestRSSI,
      waterfallBins: latestWaterfallBins,
      sampleRateHz: sampleRateHz,
      passband: latestPassband,
      bandwidthHz: kiwiBandwidthHz,
      waterfallFFTSize: latestWaterfallFFTSize,
      zoomMax: kiwiZoomMax
    )
    if telemetry == latestTelemetry {
      return
    }
    latestTelemetry = telemetry
    enqueueTelemetry(.kiwi(telemetry))
  }

  private func emitKiwiTuning() {
    guard
      latestTunedFrequencyHz != lastReportedTunedFrequencyHz
        || latestTunedMode != lastReportedTunedMode
        || latestBandName != lastReportedBandName
        || latestPassband != lastReportedPassband
    else {
      return
    }

    lastReportedTunedFrequencyHz = latestTunedFrequencyHz
    lastReportedTunedMode = latestTunedMode
    lastReportedBandName = latestBandName
    lastReportedPassband = latestPassband

    guard let frequencyHz = latestTunedFrequencyHz else {
      return
    }
    enqueueTelemetry(
      .kiwiTuning(
        frequencyHz: frequencyHz,
        mode: latestTunedMode,
        bandName: latestBandName,
        passband: latestPassband
      )
    )
  }

  private func parseKiwiFrequencyHz(_ rawValue: String) -> Int? {
    guard let value = Double(rawValue), value.isFinite, value > 0 else { return nil }
    let absolute = abs(value)

    if absolute >= 1_000_000 {
      return Int(absolute.rounded())
    }
    if absolute >= 10_000 {
      return Int((absolute * 1_000.0).rounded())
    }
    if absolute >= 100 {
      // Kiwi frequency values are usually in kHz (e.g. 7050, 92800).
      return Int((absolute * 1_000.0).rounded())
    }
    // Very small values are typically MHz with a decimal point (e.g. 7.050).
    return Int((absolute * 1_000_000.0).rounded())
  }

  private func kiwiWaterfallViewportContext() -> KiwiWaterfallViewportContext? {
    guard
      let bandwidthHz = kiwiBandwidthHz,
      let fftSize = latestWaterfallFFTSize,
      let zoomMax = kiwiZoomMax
    else {
      return nil
    }

    let context = KiwiWaterfallViewportContext(
      bandwidthHz: bandwidthHz,
      fftSize: fftSize,
      zoomMax: zoomMax
    )
    return context.isValid ? context : nil
  }

  private func kiwiWaterfallStartBin(
    frequencyHz: Int,
    zoom: Int,
    panOffsetBins: Int
  ) -> Int? {
    guard let context = kiwiWaterfallViewportContext() else { return nil }
    return context.startBin(
      frequencyHz: frequencyHz,
      zoom: zoom,
      panOffsetBins: RadioSessionSettings.clampedKiwiWaterfallPanOffsetBins(panOffsetBins)
    )
  }

  private func applyKiwiConfigPayload(_ payload: String, tuningChanged: inout Bool) {
    guard let data = payload.data(using: .utf8) else { return }
    guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else { return }
    guard let dictionary = object as? [String: Any] else { return }

    if let rawFrequency = dictionary["freq"] as? NSNumber {
      if let parsedFrequencyHz = parseKiwiFrequencyHz(rawFrequency.stringValue) {
        latestTunedFrequencyHz = parsedFrequencyHz
        tuningChanged = true
      }
    } else if let rawFrequencyText = dictionary["freq"] as? String,
      let parsedFrequencyHz = parseKiwiFrequencyHz(rawFrequencyText) {
      latestTunedFrequencyHz = parsedFrequencyHz
      tuningChanged = true
    }

    if let modeText = dictionary["mode"] as? String,
      let mode = demodulationModeFromKiwi(modeText) {
      latestTunedMode = mode
      tuningChanged = true
    }

    let currentMode = latestTunedMode ?? .am
    let lowCut = parseKiwiPassbandCut(dictionary["low_cut"])
    let highCut = parseKiwiPassbandCut(dictionary["high_cut"])
    if lowCut != nil || highCut != nil {
      let currentPassband = latestPassband ?? RadioSessionSettings.default.kiwiPassband(for: currentMode, sampleRateHz: sampleRateHz)
      let mergedPassband = RadioSessionSettings.normalizedKiwiBandpass(
        ReceiverBandpass(
          lowCut: lowCut ?? currentPassband.lowCut,
          highCut: highCut ?? currentPassband.highCut
        ),
        mode: currentMode,
        sampleRateHz: sampleRateHz
      )
      if latestPassband != mergedPassband {
        latestPassband = mergedPassband
        tuningChanged = true
      }
    }

    if let bandText = dictionary["band"] as? String {
      let normalized = bandText.trimmingCharacters(in: .whitespacesAndNewlines)
      latestBandName = normalized.isEmpty ? nil : normalized
      tuningChanged = true
    }
  }

  private func parseKiwiPassbandCut(_ rawValue: Any?) -> Int? {
    switch rawValue {
    case let number as NSNumber:
      return number.intValue
    case let text as String:
      return parseKiwiPassbandCut(text)
    default:
      return nil
    }
  }

  private func parseKiwiPassbandCut(_ rawValue: String?) -> Int? {
    guard let rawValue else { return nil }
    if let integer = Int(rawValue) {
      return integer
    }
    guard let doubleValue = Double(rawValue), doubleValue.isFinite else { return nil }
    return Int(doubleValue.rounded())
  }

  private func enqueueTelemetry(_ event: BackendTelemetryEvent) {
    telemetryQueue.append(event)
    if telemetryQueue.count > 32 {
      telemetryQueue.removeFirst(telemetryQueue.count - 32)
    }
  }

  private func handleReceiveFailure(_ error: Error, stream: StreamKind) {
    switch stream {
    case .sound:
      if lastServerMessage == nil || lastServerMessage?.isEmpty == true {
        lastServerMessage = error.localizedDescription
      }
      sndKeepAliveTask?.cancel()
      sndKeepAliveTask = nil
      sndReceiveTask = nil
      sndSocket = nil
      log("Sound stream failed: \(error.localizedDescription)", severity: .error)
    case .waterfall:
      wfKeepAliveTask?.cancel()
      wfKeepAliveTask = nil
      wfReceiveTask = nil
      wfSocket = nil
      log("Waterfall stream failed: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func makeKiwiEndpointKey(for url: URL, basePath: String) -> String {
    let scheme = url.scheme?.lowercased() ?? "ws"
    let host = url.host?.lowercased() ?? "unknown"
    let defaultPort = scheme == "wss" ? 443 : 80
    let port = url.port ?? defaultPort
    let normalizedBasePath = pathWithTrailingSlash(basePath).lowercased()
    return "\(scheme)://\(host):\(port)\(normalizedBasePath)"
  }

  private func shouldDisableWaterfall(for message: String) -> Bool {
    message == "Multiple connections from the same IP are not allowed."
      || message == "KiwiSDR is currently busy (all client slots are used)."
  }

  private func blockedWaterfallReason() async -> String? {
    guard let kiwiEndpointKey else { return nil }
    return await KiwiWaterfallAvailabilityStore.shared.blockedReason(for: kiwiEndpointKey)
  }

  private func disableWaterfallForCurrentEndpoint(reason: String) async {
    guard let kiwiEndpointKey else { return }
    pendingWaterfallActivationTask?.cancel()
    pendingWaterfallActivationTask = nil
    let existingReason = await KiwiWaterfallAvailabilityStore.shared.blockedReason(for: kiwiEndpointKey)
    if existingReason == reason {
      closeWaterfallStream(clearTelemetry: true)
      return
    }
    await KiwiWaterfallAvailabilityStore.shared.rememberBlocked(endpointKey: kiwiEndpointKey, reason: reason)
    log("Disabling Kiwi waterfall for current endpoint: \(reason)", severity: .warning)
    closeWaterfallStream(clearTelemetry: true)
  }

  private func scheduleWaterfallActivationIfNeeded(reason: String) async {
    guard runtimePolicy.allowsVisualTelemetry else { return }
    guard wfSocket == nil else { return }
    guard pendingWaterfallActivationTask == nil else { return }
    guard let activeProfile else { return }
    guard receivedAudioFrameCount >= kiwiStableAudioFrameThreshold else { return }
    if await blockedWaterfallReason() != nil { return }

    let delaySeconds: TimeInterval
    if let firstAudioFrameAt {
      let elapsed = Date().timeIntervalSince(firstAudioFrameAt)
      delaySeconds = max(0, kiwiStableAudioWaterfallDelaySeconds - elapsed)
    } else {
      delaySeconds = kiwiStableAudioWaterfallDelaySeconds
    }

    log(
      "Scheduling Kiwi waterfall stream after stable audio: reason=\(reason), frames=\(receivedAudioFrameCount), delay=\(String(format: "%.1f", delaySeconds)) s"
    )

    let profileID = activeProfile.id
    let profile = activeProfile
    let basePath = activeBasePath
    pendingWaterfallActivationTask = Task { [self] in
      if delaySeconds > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
      }
      await activateWaterfallIfEligible(profileID: profileID, profile: profile, basePath: basePath, reason: reason)
    }
  }

  private func activateWaterfallIfEligible(
    profileID: UUID,
    profile: SDRConnectionProfile,
    basePath: String,
    reason: String
  ) async {
    defer {
      pendingWaterfallActivationTask = nil
    }

    guard !Task.isCancelled else { return }
    guard runtimePolicy.allowsVisualTelemetry else { return }
    guard wfSocket == nil else { return }
    guard activeProfile?.id == profileID else { return }
    guard receivedAudioFrameCount >= kiwiStableAudioFrameThreshold else { return }
    if await blockedWaterfallReason() != nil { return }

    do {
      log("Opening Kiwi waterfall stream after stable audio: \(reason)")
      try await openWaterfallStream(profile: profile, basePath: basePath)
      if let lastAppliedSettings {
        try? await applyKiwiWaterfallSettings(lastAppliedSettings)
      }
    } catch {
      log("Unable to open Kiwi waterfall stream after stable audio: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "KiwiSDR",
      message: message
    )
  }
}

actor OpenWebRXClient: SDRBackendClient {
  private struct BandPlanJSONEntry: Decodable {
    let name: String
    let lower_bound: Int
    let upper_bound: Int
    let tags: [String]?
    let frequencies: [String: BandPlanJSONFrequency]?
  }

  private enum BandPlanJSONFrequency: Decodable {
    case single(Int)
    case list([Int])

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let intValue = try? container.decode(Int.self) {
        self = .single(intValue)
        return
      }
      if let doubleValue = try? container.decode(Double.self) {
        self = .single(Int(doubleValue.rounded()))
        return
      }
      if let intArray = try? container.decode([Int].self) {
        self = .list(intArray)
        return
      }
      if let doubleArray = try? container.decode([Double].self) {
        self = .list(doubleArray.map { Int($0.rounded()) })
        return
      }
      throw DecodingError.typeMismatch(
        BandPlanJSONFrequency.self,
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported band frequency format")
      )
    }
  }

  let backend: SDRBackend = .openWebRX

  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var centerFrequencyHz: Int?
  private var sampleRateHz: Int?
  private var lastAppliedSettings: RadioSessionSettings?
  private var lastServerMessage: String?
  private var pendingStatusUpdate: String?
  private var outputRateHz = 12_000
  private var hdOutputRateHz = 48_000
  private var audioCompression = "none"
  private var adpcmDecoder = OpenWebRXSyncADPCMDecoder()
  private var telemetryQueue: [BackendTelemetryEvent] = []
  private var knownProfiles: [OpenWebRXProfileOption] = []
  private var selectedProfileID: String?
  private var serverBookmarks: [SDRServerBookmark] = []
  private var dialBookmarks: [SDRServerBookmark] = []
  private var bandPlanLoaded = false
  private var officialBandPlan: [SDRBandPlanEntry] = []
  private var serverBandPlan: [SDRBandPlanEntry] = []
  private var receivedAudioFrameCount = 0
  private var audioWatchdogTask: Task<Void, Never>?
  private var lastReportedFrequencyHz: Int?
  private var lastReportedMode: DemodulationMode?
  private var hasReceivedInitialServerTuning = false

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let wsPath = "\(basePath)ws/"
    let url = try await resolveWebSocketURL(profile: profile, path: wsPath)
    log("Connecting to \(url.absoluteString)")

    var request = URLRequest(url: url)
    request.applyListenSDRNetworkIdentity()
    let task = URLSession.shared.webSocketTask(with: request)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }
    audioWatchdogTask = Task {
      try? await Task.sleep(nanoseconds: 6_000_000_000)
      self.logMissingAudioIfNeeded()
    }

    try await send(ListenSDRNetworkIdentity.openWebRXHandshake)
    log("Handshake sent")
    try await sendJSON(
      [
        "type": "connectionproperties",
        "params": [
          "output_rate": outputRateHz,
          "hd_output_rate": hdOutputRateHz
        ]
      ]
    )
    try await sendJSON(
      [
        "type": "dspcontrol",
        "action": "start"
      ]
    )
    log("DSP start sent")

    Task {
      await self.loadBandPlanIfNeeded()
    }
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    centerFrequencyHz = nil
    sampleRateHz = nil
    lastServerMessage = nil
    pendingStatusUpdate = nil
    audioCompression = "none"
    outputRateHz = 12_000
    hdOutputRateHz = 48_000
    adpcmDecoder.reset()
    telemetryQueue.removeAll()
    knownProfiles = []
    selectedProfileID = nil
    serverBookmarks = []
    dialBookmarks = []
    bandPlanLoaded = false
    officialBandPlan = []
    serverBandPlan = []
    receivedAudioFrameCount = 0
    audioWatchdogTask?.cancel()
    audioWatchdogTask = nil
    lastReportedFrequencyHz = nil
    lastReportedMode = nil
    hasReceivedInitialServerTuning = false
    lastAppliedSettings = nil

    await MainActor.run {
      SharedAudioOutput.engine.stop()
    }
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }
    lastAppliedSettings = settings

    try await sendJSON(
      [
        "type": "dspcontrol",
        "params": openWebRXParams(from: settings)
      ]
    )
    log(
      "Applied tuning: mode=\(openWebRXMode(from: settings.mode)) freq=\(settings.frequencyHz) Hz"
    )
  }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func consumeStatusUpdate() async -> String? {
    defer { pendingStatusUpdate = nil }
    return pendingStatusUpdate
  }

  func consumeTelemetryUpdate() async -> BackendTelemetryEvent? {
    guard !telemetryQueue.isEmpty else { return nil }
    return telemetryQueue.removeFirst()
  }

  func sendControl(_ command: BackendControlCommand) async throws {
    switch command {
    case .selectOpenWebRXProfile(let profileID):
      try await sendJSON(
        [
          "type": "selectprofile",
          "params": [
            "profile": profileID
          ]
        ]
      )
      selectedProfileID = profileID
      emitProfiles()
      log("Profile selected: \(profileID)")

    case .setOpenWebRXSquelchLevel(let level, let enabled):
      var snapshot = lastAppliedSettings ?? .default
      snapshot.squelchEnabled = enabled
      snapshot.openWebRXSquelchLevel = RadioSessionSettings.clampedOpenWebRXSquelchLevel(level)
      lastAppliedSettings = snapshot
      try await sendJSON(
        [
          "type": "dspcontrol",
          "params": [
            "squelch_level": SquelchRuntimeControl.openWebRXSquelchLevel(
              enabled: snapshot.squelchEnabled,
              level: snapshot.openWebRXSquelchLevel
            )
          ]
        ]
      )
      log("OpenWebRX squelch updated: enabled=\(snapshot.squelchEnabled) level=\(snapshot.openWebRXSquelchLevel) dB")

    default:
      throw SDRClientError.unsupported("OpenWebRX does not support this control.")
    }
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func resolveWebSocketURL(profile: SDRConnectionProfile, path: String) async throws -> URL {
    let fallbackURL = try makeWebSocketURL(profile: profile, path: path)
    let probeURL = try makeHTTPURL(profile: profile, path: path)
    let delegate = HTTPRedirectCaptureDelegate()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 6
    configuration.timeoutIntervalForResource = 6
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer {
      session.invalidateAndCancel()
    }

    var request = URLRequest(url: probeURL)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.timeoutInterval = 6

    do {
      _ = try await session.data(for: request, delegate: delegate)
    } catch {
      if let redirectURL = delegate.redirectURL,
        let resolvedURL = websocketURL(fromHTTPRedirect: redirectURL),
        resolvedURL != fallbackURL {
        log("Resolved OpenWebRX redirect: \(fallbackURL.absoluteString) -> \(resolvedURL.absoluteString)")
        return resolvedURL
      }
      return fallbackURL
    }

    if let redirectURL = delegate.redirectURL,
      let resolvedURL = websocketURL(fromHTTPRedirect: redirectURL),
      resolvedURL != fallbackURL {
      log("Resolved OpenWebRX redirect: \(fallbackURL.absoluteString) -> \(resolvedURL.absoluteString)")
      return resolvedURL
    }

    return fallbackURL
  }

  private func openWebRXParams(from settings: RadioSessionSettings) -> [String: Any] {
    let mode = openWebRXMode(from: settings.mode)
    let passband = openWebRXBandpass(for: settings.mode)
    let offset = boundedOpenWebRXOffset(for: settings.frequencyHz)
    let squelchLevel = SquelchRuntimeControl.openWebRXSquelchLevel(
      enabled: settings.squelchEnabled,
      level: RadioSessionSettings.clampedOpenWebRXSquelchLevel(settings.openWebRXSquelchLevel)
    )

    return [
      "mod": mode,
      "offset_freq": offset,
      "low_cut": passband.lowCut,
      "high_cut": passband.highCut,
      "squelch_level": squelchLevel
    ]
  }

  private func boundedOpenWebRXOffset(for frequencyHz: Int) -> Int {
    guard let centerFrequencyHz else {
      return 0
    }
    let requestedOffset = frequencyHz - centerFrequencyHz
    guard let sampleRateHz, sampleRateHz > 2_000 else {
      return requestedOffset
    }

    // Keep offset inside currently visible baseband span.
    let maxOffset = max((sampleRateHz / 2) - 1_000, 0)
    let clamped = min(max(requestedOffset, -maxOffset), maxOffset)
    if clamped != requestedOffset {
      pendingStatusUpdate = "Frequency was clamped to receiver profile bandwidth."
    }
    return clamped
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
  }

  private func sendJSON(_ payload: [String: Any]) async throws {
    let text = try encodeJSONString(payload)
    try await send(text)
  }

  private func receiveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text)
        case .data(let data):
          await handleBinaryData(data)
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error)
        break
      }
    }
  }

  private func handleInboundText(_ text: String) async {
    if text.hasPrefix("CLIENT DE SERVER") {
      log("Handshake acknowledged by server")
      return
    }

    guard let data = text.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = parsed["type"] as? String
    else {
      return
    }

    switch type {
    case "config", "update":
      let value = (parsed["value"] as? [String: Any]) ?? [:]

      if let compression = value["audio_compression"] as? String {
        audioCompression = compression
        log("Audio compression: \(compression)")
      }
      if let outputRate = extractInt(value["output_rate"]) {
        outputRateHz = max(8_000, outputRate)
        log("Audio output rate: \(outputRateHz) Hz")
      }
      if let hdOutputRate = extractInt(value["hd_output_rate"]) {
        hdOutputRateHz = max(8_000, hdOutputRate)
        log("HD audio output rate: \(hdOutputRateHz) Hz")
      }
      if let sampleRate = extractInt(value["samp_rate"]) {
        sampleRateHz = max(2_000, sampleRate)
      }

      if let centerFrequency = extractInt(value["center_freq"]) {
        let centerChanged = centerFrequency != centerFrequencyHz
        centerFrequencyHz = centerFrequency

        if centerChanged, hasReceivedInitialServerTuning, let settings = lastAppliedSettings {
          try? await sendJSON(
            [
              "type": "dspcontrol",
              "params": openWebRXParams(from: settings)
            ]
          )
        }
      }

      if let tunedFrequencyHz = extractOpenWebRXTunedFrequency(from: value) {
        let mode = DemodulationMode.fromOpenWebRX(stringify(value["mod"]))
        emitOpenWebRXTuning(frequencyHz: tunedFrequencyHz, mode: mode)
      }

      if let sdrID = stringify(value["sdr_id"]),
        let profileID = stringify(value["profile_id"]) {
        selectedProfileID = "\(sdrID)|\(profileID)"
        emitProfiles()
      }

    case "profiles":
      guard let value = parsed["value"] as? [[String: Any]] else { return }
      let parsedProfiles = value.compactMap { profileRaw -> OpenWebRXProfileOption? in
        guard
          let id = profileRaw["id"] as? String,
          let name = profileRaw["name"] as? String
        else {
          return nil
        }
        return OpenWebRXProfileOption(id: id, name: name)
      }
      knownProfiles = parsedProfiles.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      emitProfiles()

    case "bookmarks":
      if let value = extractJSONObjectArray(parsed["value"]) {
        serverBookmarks = parseBookmarks(from: value, source: "server")
        emitBookmarks()
      }

    case "dial_frequencies":
      if let value = extractJSONObjectArray(parsed["value"]) {
        dialBookmarks = parseBookmarks(from: value, source: "dial")
        emitBookmarks()
      }

    case "bands":
      if let value = extractJSONObjectArray(parsed["value"]) {
        serverBandPlan = parseBandPlanEntries(from: value)
        emitBandPlan()
        log("Loaded server band plan (\(serverBandPlan.count) bands)")
      }

    case "sdr_error", "demodulator_error":
      if let message = parsed["value"] as? String {
        lastServerMessage = message
        log("Server error: \(message)", severity: .error)
      }

    default:
      break
    }
  }

  private func handleBinaryData(_ data: Data) async {
    guard data.count > 1 else { return }

    let frameType = data[0]
    let payload = Data(data.dropFirst())

    switch frameType {
    case 2:
      await playAudio(payload, sampleRate: Double(outputRateHz), frameType: frameType)

    case 4:
      await playAudio(payload, sampleRate: Double(hdOutputRateHz), frameType: frameType)

    default:
      break
    }
  }

  private func playAudio(_ payload: Data, sampleRate: Double, frameType: UInt8) async {
    guard !payload.isEmpty else { return }

    let pcm: [Int16]
    if audioCompression.lowercased() == "adpcm" {
      pcm = adpcmDecoder.decodeWithSync(payload)
    } else {
      pcm = decodeInt16PCM(payload, littleEndian: true)
    }

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }
    receivedAudioFrameCount += 1
    audioWatchdogTask?.cancel()
    audioWatchdogTask = nil
    if receivedAudioFrameCount <= 3 {
      let rms = sqrt(floats.reduce(0) { $0 + ($1 * $1) } / Float(max(floats.count, 1)))
      log(
        String(
          format: "Audio frame #%d received (type=%d, rate=%d Hz, compression=%@, rms=%.4f)",
          receivedAudioFrameCount,
          Int(frameType),
          Int(sampleRate.rounded()),
          audioCompression,
          rms
        )
      )
    }

    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func logMissingAudioIfNeeded() {
    guard socket != nil else { return }
    guard receivedAudioFrameCount == 0 else { return }
    pendingStatusUpdate = NSLocalizedString(
      "Connected, but OpenWebRX is not sending audio.",
      comment: "Status shown when OpenWebRX is connected but audio frames are missing"
    )
    log("Connected, but no OpenWebRX audio frames were received within 6 seconds.", severity: .warning)
  }

  private func extractInt(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let doubleValue = value as? Double, doubleValue.isFinite {
      return Int(doubleValue.rounded())
    }
    if let floatValue = value as? Float, floatValue.isFinite {
      return Int(floatValue.rounded())
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let text = value as? String {
      let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
      if let intValue = Int(normalized) {
        return intValue
      }
      if let doubleValue = Double(normalized), doubleValue.isFinite {
        return Int(doubleValue.rounded())
      }
    }
    return nil
  }

  private func stringify(_ value: Any?) -> String? {
    if let text = value as? String {
      return text
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  private func extractJSONObjectArray(_ value: Any?) -> [[String: Any]]? {
    if let dictionaries = value as? [[String: Any]] {
      return dictionaries
    }
    if let values = value as? [Any] {
      let dictionaries = values.compactMap { $0 as? [String: Any] }
      return dictionaries.isEmpty ? nil : dictionaries
    }
    if let dictionary = value as? [String: Any] {
      let nestedArrays = dictionary.values.compactMap { nested -> [[String: Any]]? in
        if let direct = nested as? [[String: Any]] {
          return direct
        }
        if let raw = nested as? [Any] {
          let mapped = raw.compactMap { $0 as? [String: Any] }
          return mapped.isEmpty ? nil : mapped
        }
        return nil
      }
      let flattened = nestedArrays.flatMap { $0 }
      return flattened.isEmpty ? nil : flattened
    }
    return nil
  }

  private func extractOpenWebRXTunedFrequency(from payload: [String: Any]) -> Int? {
    let directKeys = [
      "start_freq",
      "freq",
      "frequency",
      "rx_freq",
      "tuned_freq",
      "vfo_freq"
    ]
    for key in directKeys {
      if let value = extractInt(payload[key]), value > 0 {
        return value
      }
    }

    let explicitCenterFrequency = extractInt(payload["center_freq"])
    let offsetKeys = [
      "offset_freq",
      "offset_frequency",
      "start_offset_freq",
      "start_offset_frequency"
    ]
    let containsOffset = offsetKeys.contains { extractInt(payload[$0]) != nil }

    let resolvedCenterFrequency: Int? = {
      if let centerFrequency = explicitCenterFrequency, centerFrequency > 0 {
        return centerFrequency
      }
      if containsOffset {
        return centerFrequencyHz
      }
      return nil
    }()

    if let center = resolvedCenterFrequency, let offset = extractInt(payload["offset_freq"]) {
      return center + offset
    }
    if let center = resolvedCenterFrequency, let offset = extractInt(payload["offset_frequency"]) {
      return center + offset
    }
    if let center = resolvedCenterFrequency, let startOffset = extractInt(payload["start_offset_freq"]) {
      return center + startOffset
    }
    if let center = resolvedCenterFrequency, let startOffset = extractInt(payload["start_offset_frequency"]) {
      return center + startOffset
    }
    if let center = explicitCenterFrequency, center > 0 {
      return center
    }
    return nil
  }

  private func emitOpenWebRXTuning(frequencyHz: Int, mode: DemodulationMode?) {
    hasReceivedInitialServerTuning = true
    if frequencyHz == lastReportedFrequencyHz, mode == lastReportedMode {
      return
    }
    lastReportedFrequencyHz = frequencyHz
    lastReportedMode = mode
    enqueueTelemetry(.openWebRXTuning(frequencyHz: frequencyHz, mode: mode))
  }

  private func parseBookmarks(
    from entries: [[String: Any]],
    source: String
  ) -> [SDRServerBookmark] {
    var output: [SDRServerBookmark] = []
    output.reserveCapacity(entries.count)

    for entry in entries {
      let frequencyHz = extractInt(entry["frequency"]) ?? 0
      guard frequencyHz > 0 else { continue }

      let name: String = {
        if let text = entry["name"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return text
        }
        if let mode = entry["mode"] as? String, !mode.isEmpty {
          return mode.uppercased()
        }
        return FrequencyFormatter.mhzText(fromHz: frequencyHz)
      }()

      let modulationRaw = (entry["modulation"] as? String) ?? (entry["mode"] as? String)
      let bookmark = SDRServerBookmark(
        id: "\(source)|\(frequencyHz)|\(modulationRaw ?? "na")|\(name.lowercased())",
        name: name,
        frequencyHz: frequencyHz,
        modulation: .fromOpenWebRX(modulationRaw),
        source: source
      )
      output.append(bookmark)
    }

    return output.sorted {
      if $0.frequencyHz != $1.frequencyHz {
        return $0.frequencyHz < $1.frequencyHz
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func parseBandPlanEntries(from entries: [[String: Any]]) -> [SDRBandPlanEntry] {
    var output: [SDRBandPlanEntry] = []
    output.reserveCapacity(entries.count)

    for entry in entries {
      guard
        let name = stringify(entry["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty
      else {
        continue
      }

      let lowerBoundHz = extractInt(entry["lower_bound"]) ?? extractInt(entry["low_bound"]) ?? 0
      let upperBoundHz = extractInt(entry["upper_bound"]) ?? extractInt(entry["high_bound"]) ?? 0
      guard lowerBoundHz > 0, upperBoundHz > lowerBoundHz else { continue }

      let tags = (entry["tags"] as? [String]) ?? []
      let frequencies = parseBandFrequencies(from: entry["frequencies"], bandName: name)

      output.append(
        SDRBandPlanEntry(
          id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
          name: name,
          lowerBoundHz: lowerBoundHz,
          upperBoundHz: upperBoundHz,
          tags: tags,
          frequencies: frequencies
        )
      )
    }

    return output.sorted { $0.lowerBoundHz < $1.lowerBoundHz }
  }

  private func parseBandFrequencies(from rawValue: Any?, bandName: String) -> [SDRBandFrequency] {
    guard let map = rawValue as? [String: Any] else { return [] }

    var frequencies: [SDRBandFrequency] = []
    for (modeName, modeValue) in map {
      switch modeValue {
      case let single as Int:
        frequencies.append(
          SDRBandFrequency(
            id: "\(bandName)|\(modeName)|\(single)",
            name: modeName.uppercased(),
            frequencyHz: single
          )
        )
      case let single as Double where single.isFinite:
        let hz = Int(single.rounded())
        frequencies.append(
          SDRBandFrequency(
            id: "\(bandName)|\(modeName)|\(hz)",
            name: modeName.uppercased(),
            frequencyHz: hz
          )
        )
      case let list as [Int]:
        for hz in list {
          frequencies.append(
            SDRBandFrequency(
              id: "\(bandName)|\(modeName)|\(hz)",
              name: modeName.uppercased(),
              frequencyHz: hz
            )
          )
        }
      case let list as [Double]:
        for rawHz in list where rawHz.isFinite {
          let hz = Int(rawHz.rounded())
          frequencies.append(
            SDRBandFrequency(
              id: "\(bandName)|\(modeName)|\(hz)",
              name: modeName.uppercased(),
              frequencyHz: hz
            )
          )
        }
      default:
        continue
      }
    }

    return frequencies.sorted {
      if $0.frequencyHz != $1.frequencyHz {
        return $0.frequencyHz < $1.frequencyHz
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func emitProfiles() {
    guard !knownProfiles.isEmpty else { return }
    enqueueTelemetry(.openWebRXProfiles(knownProfiles, selectedID: selectedProfileID))
  }

  private func emitBookmarks() {
    var merged: [String: SDRServerBookmark] = [:]
    for item in dialBookmarks + serverBookmarks {
      merged[item.id] = item
    }
    let sorted = merged.values.sorted {
      if $0.frequencyHz != $1.frequencyHz {
        return $0.frequencyHz < $1.frequencyHz
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    enqueueTelemetry(.openWebRXBookmarks(sorted))
  }

  private func emitBandPlan() {
    let effectivePlan: [SDRBandPlanEntry]
    if serverBandPlan.isEmpty {
      effectivePlan = officialBandPlan
    } else {
      effectivePlan = mergeBandPlans(serverBandPlan, with: officialBandPlan)
    }

    guard !effectivePlan.isEmpty else { return }
    enqueueTelemetry(.openWebRXBandPlan(effectivePlan))
  }

  private func mergeBandPlans(
    _ serverEntries: [SDRBandPlanEntry],
    with officialEntries: [SDRBandPlanEntry]
  ) -> [SDRBandPlanEntry] {
    guard !officialEntries.isEmpty else { return serverEntries }

    return serverEntries.map { serverEntry in
      guard let officialMatch = bestOfficialBandMatch(for: serverEntry, in: officialEntries) else {
        return serverEntry
      }

      let mergedTags = Array(Set(serverEntry.tags + officialMatch.tags)).sorted()
      let mergedFrequencies = serverEntry.frequencies.isEmpty
        ? officialMatch.frequencies.filter { frequency in
          (serverEntry.lowerBoundHz...serverEntry.upperBoundHz).contains(frequency.frequencyHz)
        }
        : serverEntry.frequencies

      return SDRBandPlanEntry(
        id: serverEntry.id,
        name: serverEntry.name,
        lowerBoundHz: serverEntry.lowerBoundHz,
        upperBoundHz: serverEntry.upperBoundHz,
        tags: mergedTags,
        frequencies: mergedFrequencies
      )
    }
  }

  private func bestOfficialBandMatch(
    for serverEntry: SDRBandPlanEntry,
    in officialEntries: [SDRBandPlanEntry]
  ) -> SDRBandPlanEntry? {
    let normalizedServerName = serverEntry.name
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")

    if let exactNameMatch = officialEntries.first(where: {
      $0.name
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "") == normalizedServerName
    }) {
      return exactNameMatch
    }

    let overlappingEntries = officialEntries
      .map { entry in (entry: entry, overlap: overlapWidth(entry, with: serverEntry)) }
      .filter { $0.overlap > 0 }

    return overlappingEntries.max { lhs, rhs in
      lhs.overlap < rhs.overlap
    }?.entry
  }

  private func overlapWidth(_ lhs: SDRBandPlanEntry, with rhs: SDRBandPlanEntry) -> Int {
    let lower = max(lhs.lowerBoundHz, rhs.lowerBoundHz)
    let upper = min(lhs.upperBoundHz, rhs.upperBoundHz)
    return max(0, upper - lower)
  }

  private func loadBandPlanIfNeeded() async {
    if bandPlanLoaded {
      return
    }
    bandPlanLoaded = true

    guard
      let url = URL(string: "https://raw.githubusercontent.com/jketterl/openwebrx/develop/bands.json")
    else {
      return
    }

    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 20
      request.applyListenSDRNetworkIdentity()
      let (data, response) = try await URLSession.shared.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        log("Unable to fetch OpenWebRX band plan", severity: .warning)
        return
      }

      let decoded = try JSONDecoder().decode([BandPlanJSONEntry].self, from: data)
      let entries = decoded.map { raw in
        var frequencies: [SDRBandFrequency] = []
        if let map = raw.frequencies {
          for (modeName, modeValue) in map {
            switch modeValue {
            case .single(let hz):
              frequencies.append(
                SDRBandFrequency(id: "\(raw.name)|\(modeName)|\(hz)", name: modeName.uppercased(), frequencyHz: hz)
              )
            case .list(let list):
              for hz in list {
                frequencies.append(
                  SDRBandFrequency(id: "\(raw.name)|\(modeName)|\(hz)", name: modeName.uppercased(), frequencyHz: hz)
                )
              }
            }
          }
        }

        return SDRBandPlanEntry(
          id: raw.name.lowercased().replacingOccurrences(of: " ", with: "-"),
          name: raw.name,
          lowerBoundHz: raw.lower_bound,
          upperBoundHz: raw.upper_bound,
          tags: raw.tags ?? [],
          frequencies: frequencies.sorted {
            if $0.frequencyHz != $1.frequencyHz {
              return $0.frequencyHz < $1.frequencyHz
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
          }
        )
      }
      .sorted { $0.lowerBoundHz < $1.lowerBoundHz }

      officialBandPlan = entries
      emitBandPlan()
      log("Loaded OpenWebRX band plan (\(entries.count) bands)")
    } catch {
      log("Band plan load failed: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func enqueueTelemetry(_ event: BackendTelemetryEvent) {
    telemetryQueue.append(event)
    if telemetryQueue.count > 40 {
      telemetryQueue.removeFirst(telemetryQueue.count - 40)
    }
  }

  private func handleReceiveFailure(_ error: Error) {
    lastServerMessage = error.localizedDescription
    log("Receive loop failed: \(error.localizedDescription)", severity: .error)
    receiveTask = nil
    socket = nil
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "OpenWebRX",
      message: message
    )
  }
}

struct FMDXAudioRuntimeSnapshot {
  let queueStarted: Bool
  let queuedDurationSeconds: TimeInterval
  let queuedBufferCount: Int
  let secondsSinceLastAudioOutput: TimeInterval
  let secondsSinceLastLatencyTrim: TimeInterval?
}

final class FMDXMP3AudioPlayer {
  static let shared = FMDXMP3AudioPlayer()

  private let workerQueue = DispatchQueue(label: "ListenSDR.FMDXMP3AudioPlayer")
  private let queueBufferSize: Int = 64 * 1024
  private let queueBufferCount: Int = 24
  private let maxPacketsPerBuffer: Int = 1024
  private let minEnqueueBytes: Int = 8 * 1024
  private let minBuffersBeforeStart = 2
  private let maxQueuedBuffersBeforeTrim = 14
  private let latencyTrimCooldownSeconds: TimeInterval = 8
  private let latencyTrimGraceSeconds: TimeInterval = 1.25
  private let latencyTrimToleranceSeconds: TimeInterval = 0.25
  private let latencyTrimBufferTolerance = 3
  private let maxConsecutiveBufferStarvation = 180
  private var packetHoldSeconds: TimeInterval = 0.14
  private var startupBufferSeconds: TimeInterval = 0.55
  private var maxLatencySeconds: TimeInterval = 1.8

  private var fileStreamID: AudioFileStreamID?
  private var audioQueue: AudioQueueRef?
  private var streamDescription: AudioStreamBasicDescription?
  private var reusableBuffers: [AudioQueueBufferRef] = []
  private var activeBuffer: AudioQueueBufferRef?
  private var activeBufferOffset = 0
  private var activePacketCount = 0
  private var activeBufferDuration: TimeInterval = 0
  private var activeBufferStartedAt = Date.distantPast
  private var packetDescriptions: [AudioStreamPacketDescription]
  private var queueStarted = false
  private var parserNeedsDiscontinuity = true
  private var consecutiveParseErrors = 0
  private var droppedPacketCount = 0
  private var consecutiveBufferStarvation = 0
  private var lastSuccessfulEnqueueAt = Date.distantPast
  private var lastAudioRenderAt = Date.distantPast
  private var enqueuedBuffersBeforeStart = 0
  private var queuedBufferDurations: [UInt: TimeInterval] = [:]
  private var pendingQueuedDuration: TimeInterval = 0
  private var pendingQueuedBuffers = 0
  private var lastLatencyTrimAt = Date.distantPast
  private var queuedOverLimitSince = Date.distantPast

  private var desiredVolume: Float = 0.85
  private var muted = false
  private var mixWithOtherAudioApps = false
  private var isAudioSessionInterrupted = false
  private var shouldResumeAfterInterruption = false
  private var notificationTokens: [NSObjectProtocol] = []

  private init() {
    packetDescriptions = Array(
      repeating: AudioStreamPacketDescription(),
      count: maxPacketsPerBuffer
    )
    installSessionObservers()
  }

  func append(_ data: Data) {
    guard !data.isEmpty else { return }

    workerQueue.async {
      guard !self.isAudioSessionInterrupted else { return }
      self.ensureFileStreamLocked()
      guard let fileStreamID = self.fileStreamID else { return }

      data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        let flags: AudioFileStreamParseFlags = self.parserNeedsDiscontinuity ? [.discontinuity] : []
        let status = AudioFileStreamParseBytes(
          fileStreamID,
          UInt32(data.count),
          baseAddress,
          flags
        )

        if status == noErr {
          self.parserNeedsDiscontinuity = false
          self.consecutiveParseErrors = 0
        } else {
          self.parserNeedsDiscontinuity = true
          self.consecutiveParseErrors += 1
          if self.consecutiveParseErrors == 1 || self.consecutiveParseErrors % 10 == 0 {
            self.log(
              "Audio parser warning (status \(status), streak \(self.consecutiveParseErrors))",
              severity: .warning
            )
          }

          // Recover parser state only after sustained failures to avoid audio dropouts.
          if self.consecutiveParseErrors >= 30 {
            self.log("Audio parser reset after repeated failures", severity: .warning)
            self.resetLocked()
          }
        }
      }
    }
  }

  func stop() {
    workerQueue.async {
      self.resetLocked()
      self.deactivateAudioSessionIfPossible()
    }
  }

  func setVolume(_ value: Double) {
    workerQueue.async {
      self.desiredVolume = Float(min(max(value, 0), 1))
      self.applyVolumeLocked()
    }
  }

  func setMuted(_ value: Bool) {
    workerQueue.async {
      self.muted = value
      self.applyVolumeLocked()
    }
  }

  func setMixWithOtherAudioApps(_ enabled: Bool) {
    workerQueue.async {
      guard self.mixWithOtherAudioApps != enabled else { return }
      self.mixWithOtherAudioApps = enabled
      let sampleRate = self.streamDescription?.mSampleRate ?? 0
      self.configureAudioSessionIfNeeded(sampleRate: sampleRate)
    }
  }

  func setPlaybackTuning(
    startupBufferSeconds: Double,
    maxLatencySeconds: Double,
    packetHoldSeconds: Double
  ) {
    workerQueue.async {
      self.startupBufferSeconds = startupBufferSeconds
      self.maxLatencySeconds = max(maxLatencySeconds, startupBufferSeconds + 0.25)
      self.packetHoldSeconds = packetHoldSeconds
      self.log(
        String(
          format: "FM-DX audio tuning updated (start %.2f s, max %.2f s, hold %.2f s)",
          self.startupBufferSeconds,
          self.maxLatencySeconds,
          self.packetHoldSeconds
        )
      )
      if self.queueStarted && self.pendingQueuedDuration > self.maxLatencySeconds {
        self.restartOutputQueueLocked(
          reason: String(
            format: "Applying new FM-DX audio latency target (%.2f s queued, limit %.2f s)",
            self.pendingQueuedDuration,
            self.maxLatencySeconds
          )
        )
      }
    }
  }

  func secondsSinceLastAudioOutput() -> TimeInterval {
    workerQueue.sync {
      let referenceDate = lastAudioRenderAt != .distantPast ? lastAudioRenderAt : lastSuccessfulEnqueueAt
      return Date().timeIntervalSince(referenceDate)
    }
  }

  func isSessionInterrupted() -> Bool {
    workerQueue.sync { isAudioSessionInterrupted }
  }

  func runtimeSnapshot() -> FMDXAudioRuntimeSnapshot {
    workerQueue.sync {
      let referenceDate = lastAudioRenderAt != .distantPast ? lastAudioRenderAt : lastSuccessfulEnqueueAt
      let secondsSinceLastOutput = Date().timeIntervalSince(referenceDate)
      let secondsSinceLastTrim = lastLatencyTrimAt == .distantPast
        ? nil
        : Date().timeIntervalSince(lastLatencyTrimAt)

      return FMDXAudioRuntimeSnapshot(
        queueStarted: queueStarted,
        queuedDurationSeconds: pendingQueuedDuration,
        queuedBufferCount: pendingQueuedBuffers,
        secondsSinceLastAudioOutput: secondsSinceLastOutput,
        secondsSinceLastLatencyTrim: secondsSinceLastTrim
      )
    }
  }

  private func ensureFileStreamLocked() {
    guard fileStreamID == nil else { return }

    var streamID: AudioFileStreamID?
    let status = AudioFileStreamOpen(
      Unmanaged.passUnretained(self).toOpaque(),
      Self.fileStreamPropertyListener,
      Self.fileStreamPacketsCallback,
      kAudioFileMP3Type,
      &streamID
    )

    if status == noErr {
      fileStreamID = streamID
    } else {
      log("Unable to open MP3 stream parser (status \(status))", severity: .error)
    }
  }

  private func ensureAudioQueueLocked(for description: AudioStreamBasicDescription, fileStreamID: AudioFileStreamID) {
    guard audioQueue == nil else { return }

    configureAudioSessionIfNeeded(sampleRate: description.mSampleRate)

    var mutableDescription = description
    var queue: AudioQueueRef?
    let status = AudioQueueNewOutput(
      &mutableDescription,
      Self.audioQueueCallback,
      Unmanaged.passUnretained(self).toOpaque(),
      nil,
      nil,
      0,
      &queue
    )

    guard status == noErr, let queue else {
      log("Unable to open audio output queue (status \(status))", severity: .error)
      return
    }

    audioQueue = queue
    for _ in 0..<queueBufferCount {
      var buffer: AudioQueueBufferRef?
      let bufferStatus = AudioQueueAllocateBuffer(queue, UInt32(queueBufferSize), &buffer)
      if bufferStatus == noErr, let buffer {
        reusableBuffers.append(buffer)
      } else {
        log("Unable to allocate audio buffer (status \(bufferStatus))", severity: .warning)
      }
    }

    applyMagicCookieLocked(from: fileStreamID)
    applyVolumeLocked()
    log("FM-DX audio output ready (\(Int(description.mSampleRate)) Hz)")
  }

  private func applyMagicCookieLocked(from fileStreamID: AudioFileStreamID) {
    guard let audioQueue else { return }

    var cookieSize: UInt32 = 0
    let infoStatus = AudioFileStreamGetPropertyInfo(
      fileStreamID,
      kAudioFileStreamProperty_MagicCookieData,
      &cookieSize,
      nil
    )
    guard infoStatus == noErr, cookieSize > 0 else { return }

    var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
    let getStatus = cookie.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return noErr }
      return AudioFileStreamGetProperty(
        fileStreamID,
        kAudioFileStreamProperty_MagicCookieData,
        &cookieSize,
        baseAddress
      )
    }
    guard getStatus == noErr else { return }

    _ = cookie.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return noErr }
      return AudioQueueSetProperty(
        audioQueue,
        kAudioQueueProperty_MagicCookie,
        baseAddress,
        cookieSize
      )
    }
  }

  private func configureAudioSessionIfNeeded(sampleRate: Double) {
    let session = AVAudioSession.sharedInstance()
    let requestedSampleRate = sampleRate.isFinite && sampleRate >= 8_000 && sampleRate <= 192_000
      ? sampleRate
      : nil
    let options = audioSessionCategoryOptions()

    do {
      try session.setCategory(.playback, mode: .default, options: options)
      try session.setPreferredIOBufferDuration(0.010)
      if let requestedSampleRate {
        try session.setPreferredSampleRate(requestedSampleRate)
      }
      try session.setActive(true, options: [])
      log(
        "FM-DX audio session configured: requested_sample_rate_hz=\(requestedSampleRate.map { Int($0.rounded()) }?.description ?? "none") actual_sample_rate_hz=\(Int(session.sampleRate.rounded())) io_buffer_ms=\(Int((session.ioBufferDuration * 1000).rounded())) route=\(describeRoute(session.currentRoute))"
      )
    } catch {
      do {
        let fallbackOptions: AVAudioSession.CategoryOptions = mixWithOtherAudioApps ? [.mixWithOthers] : []
        try session.setCategory(.playback, mode: .default, options: fallbackOptions)
        try session.setActive(true, options: [])
        log(
          "FM-DX audio session configured with fallback options: actual_sample_rate_hz=\(Int(session.sampleRate.rounded())) route=\(describeRoute(session.currentRoute))",
          severity: .warning
        )
      } catch {
        log("Audio session setup failed: \(error.localizedDescription)", severity: .warning)
      }
    }
  }

  private func applyVolumeLocked() {
    guard let audioQueue else { return }
    _ = AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, muted ? 0 : desiredVolume)
  }

  private func audioSessionCategoryOptions() -> AVAudioSession.CategoryOptions {
    var options: AVAudioSession.CategoryOptions = [.allowAirPlay]
    if mixWithOtherAudioApps {
      options.insert(.mixWithOthers)
    }
    return options
  }

  private func resetLocked() {
    parserNeedsDiscontinuity = true

    if let fileStreamID {
      AudioFileStreamClose(fileStreamID)
      self.fileStreamID = nil
    }

    if let audioQueue {
      AudioQueueStop(audioQueue, true)
      AudioQueueDispose(audioQueue, true)
      self.audioQueue = nil
    }

    streamDescription = nil
    reusableBuffers.removeAll()
    activeBuffer = nil
    activeBufferOffset = 0
    activePacketCount = 0
    activeBufferDuration = 0
    activeBufferStartedAt = .distantPast
    queueStarted = false
    consecutiveParseErrors = 0
    droppedPacketCount = 0
    consecutiveBufferStarvation = 0
    lastSuccessfulEnqueueAt = .distantPast
    lastAudioRenderAt = .distantPast
    enqueuedBuffersBeforeStart = 0
    queuedBufferDurations.removeAll()
    pendingQueuedDuration = 0
    pendingQueuedBuffers = 0
    lastLatencyTrimAt = .distantPast
    queuedOverLimitSince = .distantPast

    DispatchQueue.main.async {
      NowPlayingMetadataController.shared.stopPlayback()
    }
  }

  private func consumeProperty(_ propertyID: AudioFileStreamPropertyID, fileStreamID: AudioFileStreamID) {
    switch propertyID {
    case kAudioFileStreamProperty_DataFormat:
      var description = AudioStreamBasicDescription()
      var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      let status = AudioFileStreamGetProperty(
        fileStreamID,
        kAudioFileStreamProperty_DataFormat,
        &size,
        &description
      )
      guard status == noErr else {
        log("Unable to read audio stream format (status \(status))", severity: .warning)
        return
      }

      streamDescription = description
      ensureAudioQueueLocked(for: description, fileStreamID: fileStreamID)

    case kAudioFileStreamProperty_MagicCookieData:
      applyMagicCookieLocked(from: fileStreamID)

    default:
      break
    }
  }

  private func consumePackets(
    numberBytes: UInt32,
    numberPackets: UInt32,
    inputData: UnsafeRawPointer,
    packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
  ) {
    if audioQueue == nil,
      !isAudioSessionInterrupted,
      let streamDescription,
      let fileStreamID {
      ensureAudioQueueLocked(for: streamDescription, fileStreamID: fileStreamID)
    }

    guard audioQueue != nil else { return }

    if let packetDescriptions, numberPackets > 0 {
      for packetIndex in 0..<Int(numberPackets) {
        let packetDescription = packetDescriptions[packetIndex]
        let packetSize = Int(packetDescription.mDataByteSize)
        guard packetSize > 0 else { continue }

        let packetStart = inputData.advanced(by: Int(packetDescription.mStartOffset))
        appendPacketLocked(packetData: packetStart, packetSize: packetSize)
      }
    } else if let bytesPerPacket = streamDescription?.mBytesPerPacket, bytesPerPacket > 0 {
      let packetSize = Int(bytesPerPacket)
      var byteOffset = 0
      while byteOffset + packetSize <= Int(numberBytes) {
        let packetStart = inputData.advanced(by: byteOffset)
        appendPacketLocked(packetData: packetStart, packetSize: packetSize)
        byteOffset += packetSize
      }
    } else {
      appendPacketLocked(packetData: inputData, packetSize: Int(numberBytes))
    }

    flushActiveBufferIfNeeded(force: false)
  }

  private func appendPacketLocked(packetData: UnsafeRawPointer, packetSize: Int) {
    guard packetSize > 0, packetSize <= queueBufferSize else { return }

    if activeBuffer == nil {
      activeBuffer = dequeueBufferLocked()
      if activeBuffer == nil {
        droppedPacketCount += 1
        consecutiveBufferStarvation += 1
        if droppedPacketCount % 50 == 0 {
          log("Dropped \(droppedPacketCount) packets because output buffers were exhausted.", severity: .warning)
        }
        if consecutiveBufferStarvation >= maxConsecutiveBufferStarvation {
          log(
            "Audio output starved for \(consecutiveBufferStarvation) packets. Resetting MP3 pipeline.",
            severity: .warning
          )
          resetLocked()
        }
      }
      activeBufferOffset = 0
      activePacketCount = 0
      activeBufferDuration = 0
      if activeBuffer != nil {
        activeBufferStartedAt = Date()
        consecutiveBufferStarvation = 0
      }
    }
    guard self.activeBuffer != nil else { return }

    if (activeBufferOffset + packetSize) > queueBufferSize || activePacketCount >= maxPacketsPerBuffer {
      enqueueActiveBufferLocked()
      guard let nextBuffer = dequeueBufferLocked() else { return }
      self.activeBuffer = nextBuffer
      activeBufferOffset = 0
      activePacketCount = 0
      activeBufferDuration = 0
      activeBufferStartedAt = Date()
    }

    guard let activeBuffer = self.activeBuffer else { return }
    let destination = activeBuffer.pointee.mAudioData.advanced(by: activeBufferOffset)
    memcpy(destination, packetData, packetSize)

    let packetDescription = AudioStreamPacketDescription(
      mStartOffset: Int64(activeBufferOffset),
      mVariableFramesInPacket: 0,
      mDataByteSize: UInt32(packetSize)
    )
    packetDescriptions[activePacketCount] = packetDescription
    activeBufferOffset += packetSize
    activePacketCount += 1
    activeBufferDuration += packetDurationSeconds(
      for: packetDescription,
      packetSize: packetSize
    )
  }

  private func dequeueBufferLocked() -> AudioQueueBufferRef? {
    guard !reusableBuffers.isEmpty else { return nil }
    return reusableBuffers.removeFirst()
  }

  private func flushActiveBufferIfNeeded(force: Bool) {
    guard activePacketCount > 0 else { return }
    if force {
      enqueueActiveBufferLocked()
      return
    }

    let heldForSeconds = Date().timeIntervalSince(activeBufferStartedAt)
    if activeBufferOffset >= minEnqueueBytes || heldForSeconds >= packetHoldSeconds {
      enqueueActiveBufferLocked()
    }
  }

  private func enqueueActiveBufferLocked() {
    guard
      let audioQueue,
      let activeBuffer,
      activePacketCount > 0
    else {
      return
    }

    activeBuffer.pointee.mAudioDataByteSize = UInt32(activeBufferOffset)
    let status = packetDescriptions.withUnsafeMutableBufferPointer { buffer in
      AudioQueueEnqueueBuffer(audioQueue, activeBuffer, UInt32(activePacketCount), buffer.baseAddress)
    }

    if status == noErr {
      lastSuccessfulEnqueueAt = Date()
      consecutiveBufferStarvation = 0
      let bufferDuration = max(activeBufferDuration, fallbackBufferDurationSeconds(packetCount: activePacketCount))
      let bufferKey = bufferIdentifier(activeBuffer)
      queuedBufferDurations[bufferKey] = bufferDuration
      pendingQueuedDuration += bufferDuration
      pendingQueuedBuffers += 1

      if !queueStarted {
        enqueuedBuffersBeforeStart += 1
        if enqueuedBuffersBeforeStart >= minBuffersBeforeStart &&
          pendingQueuedDuration >= startupBufferSeconds {
          let startStatus = AudioQueueStart(audioQueue, nil)
          if startStatus == noErr {
            queueStarted = true
            log(
              "FM-DX audio queue started with \(enqueuedBuffersBeforeStart) prebuffered chunks (\(String(format: "%.2f", pendingQueuedDuration)) s queued)"
            )
            DispatchQueue.main.async {
              NowPlayingMetadataController.shared.startPlayback(source: "FM-DX stream")
            }
          } else {
            log("Unable to start audio queue (status \(startStatus))", severity: .warning)
          }
        }
      } else {
        trimQueuedLatencyIfNeededLocked()
      }
    } else {
      reusableBuffers.append(activeBuffer)
      consecutiveBufferStarvation += 1
      log("Unable to enqueue audio packet (status \(status))", severity: .warning)
    }

    self.activeBuffer = nil
    activeBufferOffset = 0
    activePacketCount = 0
    activeBufferDuration = 0
  }

  private func recycleBuffer(_ buffer: AudioQueueBufferRef) {
    workerQueue.async {
      guard self.audioQueue != nil else { return }
      let bufferKey = self.bufferIdentifier(buffer)
      if let duration = self.queuedBufferDurations.removeValue(forKey: bufferKey) {
        self.pendingQueuedDuration = max(0, self.pendingQueuedDuration - duration)
      }
      self.pendingQueuedBuffers = max(0, self.pendingQueuedBuffers - 1)
      self.lastAudioRenderAt = Date()
      self.reusableBuffers.append(buffer)
      self.consecutiveBufferStarvation = 0
    }
  }

  private func packetDurationSeconds(
    for packetDescription: AudioStreamPacketDescription,
    packetSize: Int
  ) -> TimeInterval {
    guard let description = streamDescription, description.mSampleRate > 0 else {
      return 0
    }

    let framesPerPacket: Double
    if packetDescription.mVariableFramesInPacket > 0 {
      framesPerPacket = Double(packetDescription.mVariableFramesInPacket)
    } else if description.mFramesPerPacket > 0 {
      framesPerPacket = Double(description.mFramesPerPacket)
    } else if description.mBytesPerPacket > 0, description.mFramesPerPacket > 0 {
      framesPerPacket = (Double(packetSize) / Double(description.mBytesPerPacket)) * Double(description.mFramesPerPacket)
    } else {
      framesPerPacket = 1152
    }

    return framesPerPacket / description.mSampleRate
  }

  private func fallbackBufferDurationSeconds(packetCount: Int) -> TimeInterval {
    guard packetCount > 0 else { return 0 }
    guard let description = streamDescription, description.mSampleRate > 0 else {
      return Double(packetCount) * 0.024
    }

    let framesPerPacket = description.mFramesPerPacket > 0 ? Double(description.mFramesPerPacket) : 1152
    return Double(packetCount) * (framesPerPacket / description.mSampleRate)
  }

  private func bufferIdentifier(_ buffer: AudioQueueBufferRef) -> UInt {
    UInt(Int(bitPattern: buffer))
  }

  private func trimQueuedLatencyIfNeededLocked() {
    guard queueStarted else { return }
    guard Date().timeIntervalSince(lastLatencyTrimAt) >= latencyTrimCooldownSeconds else { return }

    let queuedTooLong = pendingQueuedDuration > (maxLatencySeconds + latencyTrimToleranceSeconds)
    let tooManyQueuedBuffers = pendingQueuedBuffers > (maxQueuedBuffersBeforeTrim + latencyTrimBufferTolerance)
    guard queuedTooLong || tooManyQueuedBuffers else {
      queuedOverLimitSince = .distantPast
      return
    }

    if queuedOverLimitSince == .distantPast {
      queuedOverLimitSince = Date()
      return
    }

    guard Date().timeIntervalSince(queuedOverLimitSince) >= latencyTrimGraceSeconds else { return }

    restartOutputQueueLocked(
      reason: "Trimming FM-DX audio latency (\(String(format: "%.2f", pendingQueuedDuration)) s queued, \(pendingQueuedBuffers) buffers)"
    )
  }

  private func restartOutputQueueLocked(reason: String) {
    lastLatencyTrimAt = Date()
    log(reason, severity: .warning)

    if let audioQueue {
      AudioQueueStop(audioQueue, true)
      AudioQueueDispose(audioQueue, true)
      self.audioQueue = nil
    }

    reusableBuffers.removeAll()
    activeBuffer = nil
    activeBufferOffset = 0
    activePacketCount = 0
    activeBufferDuration = 0
    activeBufferStartedAt = .distantPast
    queuedBufferDurations.removeAll()
    pendingQueuedDuration = 0
    pendingQueuedBuffers = 0
    queueStarted = false
    enqueuedBuffersBeforeStart = 0
    consecutiveBufferStarvation = 0
    queuedOverLimitSince = .distantPast

    guard let streamDescription, let fileStreamID else { return }
    ensureAudioQueueLocked(for: streamDescription, fileStreamID: fileStreamID)
  }

  private func deactivateAudioSessionIfPossible() {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
      log("FM-DX audio session deactivated.")
    } catch {
      log("Audio session deactivation failed: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "FM-DX Audio",
      message: message
    )
  }

  private func describeRoute(_ route: AVAudioSessionRouteDescription) -> String {
    let outputs = route.outputs.map { "\($0.portType.rawValue)=\($0.portName)" }.joined(separator: ",")
    let inputs = route.inputs.map { "\($0.portType.rawValue)=\($0.portName)" }.joined(separator: ",")
    return "outputs=[\(outputs.isEmpty ? "none" : outputs)] inputs=[\(inputs.isEmpty ? "none" : inputs)]"
  }

  private func describeRouteChangeReason(_ reason: AVAudioSession.RouteChangeReason) -> String {
    switch reason {
    case .unknown:
      return "unknown"
    case .newDeviceAvailable:
      return "new_device_available"
    case .oldDeviceUnavailable:
      return "old_device_unavailable"
    case .categoryChange:
      return "category_change"
    case .override:
      return "override"
    case .wakeFromSleep:
      return "wake_from_sleep"
    case .noSuitableRouteForCategory:
      return "no_suitable_route"
    case .routeConfigurationChange:
      return "route_configuration_change"
    @unknown default:
      return "unknown_future"
    }
  }

  private func installSessionObservers() {
    let center = NotificationCenter.default
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: nil
      ) { [weak self] notification in
        self?.workerQueue.async {
          self?.handleAudioRouteChangeLocked(notification)
        }
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereLostNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.workerQueue.async {
          self?.log("FM-DX audio media services were lost.", severity: .warning)
        }
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.workerQueue.async {
          self?.parserNeedsDiscontinuity = true
          self?.log("FM-DX audio media services were reset.", severity: .warning)
        }
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: nil
      ) { [weak self] notification in
        self?.workerQueue.async {
          self?.handleAudioSessionInterruptionLocked(notification)
        }
      }
    )
  }

  private func handleAudioSessionInterruptionLocked(_ notification: Notification) {
    guard
      let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }

    switch type {
    case .began:
      beginAudioSessionInterruptionLocked()
    case .ended:
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      endAudioSessionInterruptionLocked(shouldResume: options.contains(.shouldResume))
    @unknown default:
      break
    }
  }

  private func handleAudioRouteChangeLocked(_ notification: Notification) {
    let currentRoute = describeRoute(AVAudioSession.sharedInstance().currentRoute)
    let previousRoute = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
      .map(describeRoute) ?? "unknown"
    if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
      log(
        "FM-DX audio route changed: reason=\(describeRouteChangeReason(reason)) previous=\(previousRoute) current=\(currentRoute)"
      )
    } else {
      log("FM-DX audio route changed: previous=\(previousRoute) current=\(currentRoute)")
    }
  }

  private func beginAudioSessionInterruptionLocked() {
    guard !isAudioSessionInterrupted else { return }

    isAudioSessionInterrupted = true
    shouldResumeAfterInterruption = queueStarted || pendingQueuedBuffers > 0 || activePacketCount > 0
    parserNeedsDiscontinuity = true
    clearOutputStateForInterruptionLocked()
    log(
      "FM-DX audio session interrupted. queue_started=\(queueStarted) pending_buffers=\(pendingQueuedBuffers) active_packets=\(activePacketCount) route=\(describeRoute(AVAudioSession.sharedInstance().currentRoute))",
      severity: .warning
    )
  }

  private func endAudioSessionInterruptionLocked(shouldResume: Bool) {
    let shouldRearm = shouldResumeAfterInterruption || shouldResume
    isAudioSessionInterrupted = false
    shouldResumeAfterInterruption = false
    lastSuccessfulEnqueueAt = Date()
    lastAudioRenderAt = Date()

    guard shouldRearm else {
      log("FM-DX audio session interruption ended without resume. route=\(describeRoute(AVAudioSession.sharedInstance().currentRoute))")
      return
    }

    if let streamDescription, let fileStreamID {
      configureAudioSessionIfNeeded(sampleRate: streamDescription.mSampleRate)
      ensureAudioQueueLocked(for: streamDescription, fileStreamID: fileStreamID)
    }
    log(
      "FM-DX audio session interruption ended. should_resume=\(shouldResume) route=\(describeRoute(AVAudioSession.sharedInstance().currentRoute)). Audio will resume when stream data arrives."
    )
  }

  private func clearOutputStateForInterruptionLocked() {
    if let audioQueue {
      AudioQueueStop(audioQueue, true)
      AudioQueueDispose(audioQueue, true)
      self.audioQueue = nil
    }

    reusableBuffers.removeAll()
    activeBuffer = nil
    activeBufferOffset = 0
    activePacketCount = 0
    activeBufferDuration = 0
    activeBufferStartedAt = .distantPast
    queueStarted = false
    enqueuedBuffersBeforeStart = 0
    queuedBufferDurations.removeAll()
    pendingQueuedDuration = 0
    pendingQueuedBuffers = 0
    consecutiveBufferStarvation = 0
    lastAudioRenderAt = .distantPast
    queuedOverLimitSince = .distantPast

    DispatchQueue.main.async {
      NowPlayingMetadataController.shared.stopPlayback()
    }
  }

  private static let fileStreamPropertyListener: AudioFileStream_PropertyListenerProc = {
    userData,
    fileStreamID,
    propertyID,
    _ in
    let player = Unmanaged<FMDXMP3AudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.consumeProperty(propertyID, fileStreamID: fileStreamID)
  }

  private static let fileStreamPacketsCallback: AudioFileStream_PacketsProc = {
    userData,
    numberBytes,
    numberPackets,
    inputData,
    packetDescriptions in
    let player = Unmanaged<FMDXMP3AudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.consumePackets(
      numberBytes: numberBytes,
      numberPackets: numberPackets,
      inputData: inputData,
      packetDescriptions: packetDescriptions
    )
  }

  private static let audioQueueCallback: AudioQueueOutputCallback = {
    userData,
    _,
    buffer in
    guard let userData else { return }
    let player = Unmanaged<FMDXMP3AudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.recycleBuffer(buffer)
  }
}

actor FMDXWebserverClient: SDRBackendClient {
  let backend: SDRBackend = .fmDxWebserver
  private let cachedCapabilities: FMDXCapabilities?
  private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.urlCache = nil
    configuration.httpShouldSetCookies = true
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpCookieStorage = HTTPCookieStorage()
    return URLSession(configuration: configuration)
  }()

  private var socket: URLSessionWebSocketTask?
  private var audioSocket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var audioReceiveTask: Task<Void, Never>?
  private var pollTask: Task<Void, Never>?
  private var healthTask: Task<Void, Never>?
  private var textReconnectTask: Task<Void, Never>?
  private var audioReconnectTask: Task<Void, Never>?

  private var lastServerMessage: String?
  private var pendingStatusUpdate: String?
  private var telemetryQueue: [BackendTelemetryEvent] = []
  private var latestTelemetry: FMDXTelemetry?

  private var activeProfile: SDRConnectionProfile?
  private var activeBasePath = "/"
  private var lastAppliedSettings: RadioSessionSettings?
  private var lastCapabilities: FMDXCapabilities = .empty
  private var lastAudioPacketAt = Date.distantPast
  private var hasLoggedFirstAudioPacket = false
  private var supportsPingEndpoint: Bool?
  private var consecutivePingFailures = 0
  private var lastRealtimeStatusAt = Date.distantPast
  private let stationListRefreshInterval: TimeInterval = 90
  private let stationListRetryInterval: TimeInterval = 15
  private var nextStationListRefreshAt = Date.distantPast
  private var stationListUnavailable = false
  private var lastPublishedFMDXPresets: [SDRServerBookmark] = []
  private var lastPublishedFMDXPresetSource = "unknown"
  private var runtimePolicy: BackendRuntimePolicy = .interactive

  init(cachedCapabilities: FMDXCapabilities? = nil) {
    self.cachedCapabilities = cachedCapabilities
  }

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()
    clearSessionCookies()
    log(
      "Reset FM-DX session cookies before connect. password_present=\(!profile.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
    )
    try await authenticateIfNeeded(profile: profile)

    activeProfile = profile
    activeBasePath = pathWithTrailingSlash(profile.normalizedPath)
    lastAppliedSettings = nil
    supportsPingEndpoint = nil
    consecutivePingFailures = 0
    lastAudioPacketAt = .distantPast
    lastRealtimeStatusAt = .distantPast
    lastPublishedFMDXPresetSource = "unknown"

    try openTextSocket(profile: profile, basePath: activeBasePath)

    pollTask = Task { [profile] in
      await self.pollLoop(profile: profile)
    }

    healthTask = Task {
      await self.healthLoop()
    }

    do {
      try await connectAudio(profile: profile, basePath: activeBasePath)
    } catch {
      audioReceiveTask?.cancel()
      audioReceiveTask = nil
      audioSocket?.cancel(with: .goingAway, reason: nil)
      audioSocket = nil
      FMDXMP3AudioPlayer.shared.stop()
      log("Audio stream unavailable: \(error.localizedDescription)", severity: .warning)
      pendingStatusUpdate = "Connected without audio stream"
    }

    var staticData: [String: Any]?
    if let snapshot = try? await fetchStaticData(profile: profile) {
      staticData = snapshot
      if let tunerName = parseString(snapshot["tunerName"])?.trimmingCharacters(in: .whitespacesAndNewlines),
        !tunerName.isEmpty {
        pendingStatusUpdate = "Tuner: \(tunerName)"
      }
    }

    let html = try? await fetchIndexHTML(profile: profile, basePath: activeBasePath)
    let apiScript: String?
    do {
      apiScript = try await fetchClientScript(
        profile: profile,
        basePath: activeBasePath,
        relativePath: "js/api.js"
      )
    } catch {
      apiScript = nil
      log("Unable to fetch FM-DX client script js/api.js: \(error.localizedDescription)", severity: .warning)
    }
    let stationList = await fetchStationListBookmarks(
      profile: profile,
      staticData: staticData,
      indexHTML: html,
      basePath: activeBasePath
    )
    if stationList != lastPublishedFMDXPresets {
      lastPublishedFMDXPresets = stationList
      enqueueTelemetry(.fmdxPresets(stationList, source: lastPublishedFMDXPresetSource))
    }
    nextStationListRefreshAt = nextStationListRefreshDate(after: Date(), stationList: stationList)

    let capabilities = buildCapabilities(
      staticData: staticData,
      indexHTML: html,
      apiScript: apiScript
    )
    let resolvedCapabilities = FMDXCapabilitiesCacheCore.resolve(
      primary: ListenSDRCore.FMDXCapabilitiesPolicyCore.Capabilities(
        antennas: capabilities.antennas.map { option in
          ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption(
            id: option.id,
            label: option.label,
            legacyValue: option.legacyValue
          )
        },
        bandwidths: capabilities.bandwidths.map { option in
          ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption(
            id: option.id,
            label: option.label,
            legacyValue: option.legacyValue
          )
        },
        supportsAM: capabilities.supportsAM,
        supportsFilterControls: capabilities.supportsFilterControls,
        supportsAGCControl: capabilities.supportsAGCControl,
        requiresTunePassword: capabilities.requiresTunePassword,
        lockedToAdmin: capabilities.lockedToAdmin
      ),
      fallback: cachedCapabilities.map { cached in
        ListenSDRCore.FMDXCapabilitiesPolicyCore.Capabilities(
          antennas: cached.antennas.map { option in
            ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption(
              id: option.id,
              label: option.label,
              legacyValue: option.legacyValue
            )
          },
          bandwidths: cached.bandwidths.map { option in
            ListenSDRCore.FMDXCapabilitiesPolicyCore.ControlOption(
              id: option.id,
              label: option.label,
              legacyValue: option.legacyValue
            )
          },
          supportsAM: cached.supportsAM,
          supportsFilterControls: cached.supportsFilterControls,
          supportsAGCControl: cached.supportsAGCControl,
          requiresTunePassword: cached.requiresTunePassword,
          lockedToAdmin: cached.lockedToAdmin
        )
      }
    )
    let capabilityState = FMDXCapabilitiesSessionCore.connectedState(resolution: resolvedCapabilities)
    let effectiveCapabilities = FMDXCapabilities(
      antennas: capabilityState.capabilities.antennas.map { option in
        FMDXControlOption(id: option.id, label: option.label, legacyValue: option.legacyValue)
      },
      bandwidths: capabilityState.capabilities.bandwidths.map { option in
        FMDXControlOption(id: option.id, label: option.label, legacyValue: option.legacyValue)
      },
      supportsAM: capabilityState.capabilities.supportsAM,
      supportsFilterControls: capabilityState.capabilities.supportsFilterControls,
      supportsAGCControl: capabilityState.capabilities.supportsAGCControl,
      requiresTunePassword: capabilityState.capabilities.requiresTunePassword,
      lockedToAdmin: capabilityState.capabilities.lockedToAdmin
    )
    lastCapabilities = effectiveCapabilities
    log(
      "Resolved capabilities: supportsAM=\(effectiveCapabilities.supportsAM) scriptLoaded=\(apiScript != nil) antennas=\(effectiveCapabilities.antennas.count) bandwidths=\(effectiveCapabilities.bandwidths.count) filters=\(effectiveCapabilities.supportsFilterControls) agc=\(effectiveCapabilities.supportsAGCControl) requiresTunePassword=\(effectiveCapabilities.requiresTunePassword) lockedToAdmin=\(effectiveCapabilities.lockedToAdmin) confirmedSnapshot=\(capabilityState.hasConfirmedSnapshot) usedCachedCapabilities=\(capabilityState.usedCachedCapabilities)"
    )
    enqueueTelemetry(
      .fmdxCapabilities(
        effectiveCapabilities,
        hasConfirmedSnapshot: capabilityState.hasConfirmedSnapshot,
        usedCachedCapabilities: capabilityState.usedCachedCapabilities
      )
    )
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    audioReceiveTask?.cancel()
    audioReceiveTask = nil

    pollTask?.cancel()
    pollTask = nil

    healthTask?.cancel()
    healthTask = nil
    textReconnectTask?.cancel()
    textReconnectTask = nil
    audioReconnectTask?.cancel()
    audioReconnectTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    audioSocket?.cancel(with: .normalClosure, reason: nil)
    audioSocket = nil
    FMDXMP3AudioPlayer.shared.stop()

    lastServerMessage = nil
    pendingStatusUpdate = nil
    telemetryQueue.removeAll()
    latestTelemetry = nil

    activeProfile = nil
    activeBasePath = "/"
    lastAppliedSettings = nil
    lastCapabilities = .empty
    lastAudioPacketAt = .distantPast
    lastRealtimeStatusAt = .distantPast
    supportsPingEndpoint = nil
    consecutivePingFailures = 0
    nextStationListRefreshAt = .distantPast
    stationListUnavailable = false
    lastPublishedFMDXPresets = []
    clearSessionCookies()

    log("Disconnected")
  }

  private func clearSessionCookies() {
    guard let cookieStorage = session.configuration.httpCookieStorage else { return }
    cookieStorage.cookies?.forEach { cookieStorage.deleteCookie($0) }
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }
    lastAppliedSettings = settings

    try await sendFrequency(settings.frequencyHz)
    if lastCapabilities.supportsFilterControls {
      try await sendFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled)
    }
    if lastCapabilities.supportsAGCControl {
      try? await send("A\(settings.agcEnabled ? 1 : 0)")
    }

    FMDXMP3AudioPlayer.shared.setVolume(settings.audioVolume)
    FMDXMP3AudioPlayer.shared.setMuted(settings.audioMuted)

    if settings.mode != .fm && settings.mode != .nfm {
      pendingStatusUpdate = "FM-DX supports FM demodulation. Current mode may be ignored."
    }
  }

  func consumeServerError() async -> String? {
    defer { lastServerMessage = nil }
    return lastServerMessage
  }

  func consumeStatusUpdate() async -> String? {
    defer { pendingStatusUpdate = nil }
    return pendingStatusUpdate
  }

  func consumeTelemetryUpdate() async -> BackendTelemetryEvent? {
    guard !telemetryQueue.isEmpty else { return nil }
    return telemetryQueue.removeFirst()
  }

  func setRuntimePolicy(_ policy: BackendRuntimePolicy) async {
    guard runtimePolicy != policy else { return }
    let previousPolicy = runtimePolicy
    runtimePolicy = policy
    log("Runtime policy changed: \(previousPolicy.diagnosticsLabel) -> \(policy.diagnosticsLabel)")

    guard let activeProfile else { return }
    guard policy.allowsVisualTelemetry else {
      log("FM-DX switched to \(policy.diagnosticsLabel) runtime policy. Station list refresh deferred.")
      return
    }
    log("FM-DX switched to \(policy.diagnosticsLabel) runtime policy. Refreshing station list if needed.")
    await refreshStationListIfNeeded(profile: activeProfile)
  }

  func sendControl(_ command: BackendControlCommand) async throws {
    switch command {
    case .selectOpenWebRXProfile:
      throw SDRClientError.unsupported("FM-DX does not support OpenWebRX profile selection.")

    case .setOpenWebRXSquelchLevel:
      throw SDRClientError.unsupported("FM-DX does not support OpenWebRX squelch control.")

    case .setKiwiSquelch:
      throw SDRClientError.unsupported("FM-DX does not support Kiwi squelch control.")

    case .setKiwiWaterfall:
      throw SDRClientError.unsupported("FM-DX does not support Kiwi waterfall control.")

      case .setKiwiPassband:
        throw SDRClientError.unsupported("FM-DX does not support Kiwi passband control.")

      case .setKiwiNoiseBlanker:
        throw SDRClientError.unsupported("FM-DX does not support Kiwi noise blanker control.")

      case .setKiwiNoiseFilter:
        throw SDRClientError.unsupported("FM-DX does not support Kiwi noise filter control.")

    case .setFMDXFrequencyHz(let frequencyHz):
      try await sendFrequency(frequencyHz)

    case .setFMDXFilter(let eqEnabled, let imsEnabled):
      guard lastCapabilities.supportsFilterControls else { return }
      try await sendFilter(eqEnabled: eqEnabled, imsEnabled: imsEnabled)

    case .setFMDXAGC(let enabled):
      guard lastCapabilities.supportsAGCControl else { return }
      try await send("A\(enabled ? 1 : 0)")

    case .setFMDXForcedStereo(let enabled):
      // FM-DX protocol uses B0 for stereo and B1 for mono.
      try await send("B\(enabled ? 0 : 1)")

    case .setFMDXAntenna(let value):
      guard let safeValue = sanitizeCommandValue(value) else {
        throw SDRClientError.unsupported("Invalid FM-DX antenna value.")
      }
      try await send("Z\(safeValue)")

    case .setFMDXBandwidth(let value, let legacyValue):
      guard let safeValue = sanitizeCommandValue(value) else {
        throw SDRClientError.unsupported("Invalid FM-DX bandwidth value.")
      }
      if let legacyValue, let safeLegacy = sanitizeCommandValue(legacyValue) {
        try? await send("F\(safeLegacy)")
      }
      try await send("W\(safeValue)")
    }
  }

  func isConnected() async -> Bool {
    guard activeProfile != nil else { return false }
    return socket != nil || textReconnectTask != nil
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
  }

  private func sendFrequency(_ frequencyHz: Int) async throws {
    let frequencyKHz = max(1, Int((Double(frequencyHz) / 1000.0).rounded()))
    log("Sending FM-DX tune command: T\(frequencyKHz)")
    try await send("T\(frequencyKHz)")
  }

  private func sendFilter(eqEnabled: Bool, imsEnabled: Bool) async throws {
    let eq = eqEnabled ? 1 : 0
    let ims = imsEnabled ? 1 : 0
    try await send("G\(eq)\(ims)")
  }

  private func sendAudio(_ message: String) async throws {
    guard let audioSocket else {
      throw SDRClientError.unsupported("FM-DX audio websocket is unavailable.")
    }
    try await audioSocket.send(.string(message))
  }

  private func connectAudio(profile: SDRConnectionProfile, basePath: String) async throws {
    audioReceiveTask?.cancel()
    audioReceiveTask = nil
    audioSocket?.cancel(with: .goingAway, reason: nil)
    audioSocket = nil

    let audioURL = try makeWebSocketURL(profile: profile, path: "\(basePath)audio")
    log("Connecting audio stream: \(audioURL.absoluteString)")

    var audioRequest = URLRequest(url: audioURL)
    audioRequest.setValue(ListenSDRNetworkIdentity.fmdxUserAgent(), forHTTPHeaderField: "User-Agent")
    let task = session.webSocketTask(with: audioRequest)
    audioSocket = task
    task.resume()
    hasLoggedFirstAudioPacket = false

    audioReceiveTask = Task { [task] in
      await self.receiveAudioLoop(task: task)
    }

    let message = try encodeJSONString([
      "type": "fallback",
      "data": "mp3"
    ])
    try await sendAudio(message)
    lastAudioPacketAt = .distantPast
    log("Requested FM-DX fallback audio format: mp3")
  }

  private func openTextSocket(profile: SDRConnectionProfile, basePath: String) throws {
    receiveTask?.cancel()
    receiveTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil

    let url = try makeWebSocketURL(profile: profile, path: "\(basePath)text")
    log("Connecting to \(url.absoluteString)")

    var textRequest = URLRequest(url: url)
    textRequest.setValue(ListenSDRNetworkIdentity.fmdxUserAgent(), forHTTPHeaderField: "User-Agent")
    let task = session.webSocketTask(with: textRequest)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }
  }

  private func receiveLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .string(let text):
          await handleInboundText(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            await handleInboundText(text)
          }
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleReceiveFailure(error)
        break
      }
    }
  }

  private func receiveAudioLoop(task: URLSessionWebSocketTask) async {
    while !Task.isCancelled {
      do {
        let message = try await task.receive()
        switch message {
        case .data(let data):
          lastAudioPacketAt = Date()
          if !hasLoggedFirstAudioPacket {
            hasLoggedFirstAudioPacket = true
            log("FM-DX first audio packet received (\(data.count) bytes)")
          }
          FMDXMP3AudioPlayer.shared.append(data)
          AudioRecordingController.shared.consumeMP3(data: data)
        case .string(let text):
          await handleAudioControlText(text)
        @unknown default:
          break
        }
      } catch {
        if Task.isCancelled {
          return
        }
        handleAudioReceiveFailure(error)
        break
      }
    }
  }

  private func healthLoop() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: healthLoopIntervalNanoseconds())
      if Task.isCancelled {
        return
      }

      guard let profile = activeProfile else {
        return
      }

      if socket == nil {
        scheduleTextReconnect()
      } else {
        let hasRecentRealtimeStatus = Date().timeIntervalSince(lastRealtimeStatusAt) < 8
        if hasRecentRealtimeStatus {
          consecutivePingFailures = 0
        } else {
          let pingOK = await pingServerIfAvailable(profile: profile, basePath: activeBasePath)
          if pingOK {
            consecutivePingFailures = 0
          } else {
            consecutivePingFailures += 1
            if consecutivePingFailures >= 2 {
              consecutivePingFailures = 0
              restartTextConnection(reason: "FM-DX ping timeout. Reconnecting...")
            }
          }
        }
      }

      if audioSocket == nil {
        scheduleAudioReconnect()
      } else {
        if !FMDXMP3AudioPlayer.shared.isSessionInterrupted(),
          lastAudioPacketAt != .distantPast {
          let rendererIdleSeconds = FMDXMP3AudioPlayer.shared.secondsSinceLastAudioOutput()
          if rendererIdleSeconds > 15 {
            restartAudioConnection(reason: "FM-DX audio playback stalled. Reconnecting...")
            continue
          }
        }

        if lastAudioPacketAt != .distantPast {
          let idleSeconds = Date().timeIntervalSince(lastAudioPacketAt)
          if idleSeconds > 12 {
            restartAudioConnection(reason: "FM-DX audio stalled. Reconnecting...")
          }
        }
      }
    }
  }

  private func pollLoop(profile: SDRConnectionProfile) async {
    while !Task.isCancelled {
      let hasRecentRealtimeStatus = Date().timeIntervalSince(lastRealtimeStatusAt) < 12
      let pollIntervalNs = pollIntervalNanoseconds(hasRecentRealtimeStatus: hasRecentRealtimeStatus)
      try? await Task.sleep(nanoseconds: pollIntervalNs)
      if Task.isCancelled {
        return
      }

      do {
        let snapshot = try await fetchAPI(profile: profile)
        updateStatus(from: snapshot)
        await refreshStationListIfNeeded(profile: profile)
      } catch {
        if Task.isCancelled {
          return
        }
      }
    }
  }

  private func handleInboundText(_ text: String) async {
    if text.trimmingCharacters(in: .whitespacesAndNewlines) == "KICK" {
      lastServerMessage = "Access denied by FM-DX server."
      log(lastServerMessage ?? "Access denied", severity: .error)
      return
    }

    guard let data = text.data(using: .utf8),
      let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return
    }

    lastRealtimeStatusAt = Date()
    updateStatus(from: snapshot)
  }

  private func handleAudioControlText(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return
    }

    if trimmed == "KICK" {
      pendingStatusUpdate = "FM-DX audio denied by server"
      log("Audio stream access denied", severity: .warning)
      return
    }
  }

  private func authenticateIfNeeded(profile: SDRConnectionProfile) async throws {
    let password = profile.password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !password.isEmpty else { return }

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)login")
    let request = try URLRequest.listenSDRFMDXLoginRequest(url: url, password: password)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw SDRClientError.unsupported("FM-DX login returned invalid response.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let message = extractServerMessage(from: data)
      if let message, !message.isEmpty {
        throw SDRClientError.unsupported("FM-DX login failed: \(message)")
      }
      throw SDRClientError.unsupported("FM-DX login failed. Check tune/admin password.")
    }

    log("Authenticated on FM-DX /login endpoint")
  }

  private func fetchAPI(profile: SDRConnectionProfile) async throws -> [String: Any] {
    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)api")
    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      throw SDRClientError.unsupported("FM-DX API is unavailable.")
    }

    guard let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SDRClientError.unsupported("FM-DX API returned invalid JSON.")
    }

    return snapshot
  }

  private func fetchStaticData(profile: SDRConnectionProfile) async throws -> [String: Any] {
    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)static_data")
    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }

    return payload
  }

  private func fetchIndexHTML(profile: SDRConnectionProfile, basePath: String) async throws -> String {
    let url = try makeHTTPURL(profile: profile, path: basePath)
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue(ListenSDRNetworkIdentity.fmdxUserAgent(), forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let html = String(data: data, encoding: .utf8) else {
      throw SDRClientError.unsupported("FM-DX index page is unavailable.")
    }

    return html
  }

  private func fetchClientScript(
    profile: SDRConnectionProfile,
    basePath: String,
    relativePath: String
  ) async throws -> String {
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)\(relativePath)")
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("application/javascript,text/javascript,*/*;q=0.1", forHTTPHeaderField: "Accept")
    request.setValue(ListenSDRNetworkIdentity.fmdxUserAgent(), forHTTPHeaderField: "User-Agent")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let script = String(data: data, encoding: .utf8)
    else {
      throw SDRClientError.unsupported("FM-DX client script is unavailable.")
    }

    return script
  }

  private func pingServerIfAvailable(profile: SDRConnectionProfile, basePath: String) async -> Bool {
    if supportsPingEndpoint == false {
      return true
    }

    do {
      let url = try makeHTTPURL(profile: profile, path: "\(basePath)ping")
      var request = URLRequest(url: url)
      request.timeoutInterval = 4
      request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

      let (_, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return false
      }

      if httpResponse.statusCode == 404 {
        supportsPingEndpoint = false
        return true
      }

      if (200...299).contains(httpResponse.statusCode) {
        supportsPingEndpoint = true
        return true
      }

      return false
    } catch {
      return false
    }
  }

  private func restartTextConnection(reason: String) {
    guard activeProfile != nil else { return }
    log(reason, severity: .warning)
    pendingStatusUpdate = reason
    receiveTask?.cancel()
    receiveTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    scheduleTextReconnect()
  }

  private func restartAudioConnection(reason: String) {
    guard activeProfile != nil else { return }
    log(reason, severity: .warning)
    pendingStatusUpdate = reason
    audioReceiveTask?.cancel()
    audioReceiveTask = nil
    audioSocket?.cancel(with: .goingAway, reason: nil)
    audioSocket = nil
    hasLoggedFirstAudioPacket = false
    FMDXMP3AudioPlayer.shared.stop()
    scheduleAudioReconnect()
  }

  private func scheduleTextReconnect() {
    guard activeProfile != nil else { return }
    guard textReconnectTask == nil else { return }

    pendingStatusUpdate = "FM-DX control stream interrupted. Reconnecting..."
    textReconnectTask = Task {
      await self.runTextReconnectLoop()
    }
  }

  private func runTextReconnectLoop() async {
    defer { textReconnectTask = nil }
    var delaySeconds: UInt64 = 1

    while !Task.isCancelled {
      guard let profile = activeProfile else { return }
      if socket != nil { return }

      try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
      if Task.isCancelled { return }

      do {
        try await authenticateIfNeeded(profile: profile)
        try openTextSocket(profile: profile, basePath: activeBasePath)

        if let settings = lastAppliedSettings {
          try? await apply(settings: settings)
        }

        pendingStatusUpdate = "FM-DX control stream restored"
        scheduleAudioReconnect()
        return
      } catch {
        log("Text reconnect attempt failed: \(error.localizedDescription)", severity: .warning)
        delaySeconds = min(delaySeconds * 2, 12)
      }
    }
  }

  private func scheduleAudioReconnect() {
    guard activeProfile != nil else { return }
    guard audioSocket == nil else { return }
    guard audioReconnectTask == nil else { return }

    pendingStatusUpdate = "FM-DX audio interrupted. Reconnecting..."
    audioReconnectTask = Task {
      await self.runAudioReconnectLoop()
    }
  }

  private func runAudioReconnectLoop() async {
    defer { audioReconnectTask = nil }
    var delaySeconds: UInt64 = 1

    while !Task.isCancelled {
      guard let profile = activeProfile else { return }
      if audioSocket != nil { return }

      if socket == nil {
        delaySeconds = min(delaySeconds * 2, 12)
        try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
        continue
      }

      do {
        try await connectAudio(profile: profile, basePath: activeBasePath)
        pendingStatusUpdate = "FM-DX audio stream restored"
        return
      } catch {
        log("Audio reconnect attempt failed: \(error.localizedDescription)", severity: .warning)
        delaySeconds = min(delaySeconds * 2, 12)
      }

      try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
    }
  }

  private func buildCapabilities(
    staticData: [String: Any]?,
    indexHTML: String?,
    apiScript: String?
  ) -> FMDXCapabilities {
    let antennas = parseAntennaOptions(from: staticData)
    let bandwidths = parseBandwidthOptions(from: indexHTML)
    let supportsAM = parseAMSupport(staticData: staticData, indexHTML: indexHTML, apiScript: apiScript)
    let supportsFilterControls = parseFilterControlSupport(indexHTML: indexHTML)
    let supportsAGCControl = parseAGCSupport(indexHTML: indexHTML)
    let requiresTunePassword = parseTunePasswordRequirement(indexHTML: indexHTML)
    let lockedToAdmin = parseAdminLockRequirement(indexHTML: indexHTML)
    return FMDXCapabilities(
      antennas: antennas,
      bandwidths: bandwidths,
      supportsAM: supportsAM,
      supportsFilterControls: supportsFilterControls,
      supportsAGCControl: supportsAGCControl,
      requiresTunePassword: requiresTunePassword,
      lockedToAdmin: lockedToAdmin
    )
  }

  private func parseAntennaOptions(from staticData: [String: Any]?) -> [FMDXControlOption] {
    guard
      let staticData,
      let antennas = staticData["ant"] as? [String: Any],
      parseBool(antennas["enabled"]) == true
    else {
      return []
    }

    var options: [FMDXControlOption] = []
    for index in 1...4 {
      let key = "ant\(index)"
      guard
        let entry = antennas[key] as? [String: Any],
        parseBool(entry["enabled"]) == true
      else {
        continue
      }

      let rawName = parseString(entry["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let label = rawName.isEmpty ? "Antenna \(index)" : rawName
      options.append(
        FMDXControlOption(
          id: String(index - 1),
          label: label,
          legacyValue: nil
        )
      )
    }

    return options
  }

  private func parseBandwidthOptions(from html: String?) -> [FMDXControlOption] {
    guard let html, !html.isEmpty else { return [] }
    let blockPattern = #"(?is)<div[^>]*id=\"data-bw(?:-phone)?\"[^>]*>.*?<ul[^>]*class=\"options[^\"]*\"[^>]*>(.*?)</ul>"#
    let itemPattern = #"(?is)<li[^>]*data-value=\"([^\"]+)\"(?:[^>]*data-value2=\"([^\"]*)\")?[^>]*class=\"option\"[^>]*>(.*?)</li>"#

    var options: [FMDXControlOption] = []
    var seen = Set<String>()

    for block in captures(for: blockPattern, in: html, group: 1) {
      guard let regex = try? NSRegularExpression(pattern: itemPattern, options: []) else {
        continue
      }

      let nsBlock = block as NSString
      let matches = regex.matches(in: block, options: [], range: NSRange(location: 0, length: nsBlock.length))
      for match in matches {
        guard match.numberOfRanges >= 4 else { continue }

        let value = nsBlock.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { continue }

        let legacyRange = match.range(at: 2)
        let legacyValue = legacyRange.location != NSNotFound
          ? nsBlock.substring(with: legacyRange).trimmingCharacters(in: .whitespacesAndNewlines)
          : nil

        let labelHTML = nsBlock.substring(with: match.range(at: 3))
        let label = decodeHTMLEntities(stripHTMLTags(labelHTML)).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLabel = label.isEmpty ? value : label
        let dedupeKey = "\(value)|\(legacyValue ?? "")"
        if seen.contains(dedupeKey) { continue }
        seen.insert(dedupeKey)

        options.append(
          FMDXControlOption(
            id: value,
            label: safeLabel,
            legacyValue: legacyValue?.isEmpty == true ? nil : legacyValue
          )
        )
      }
    }

    return options
  }

  func parseAMSupport(
    staticData: [String: Any]?,
    indexHTML: String?,
    apiScript: String? = nil
  ) -> Bool {
    var fmOnlyHintDetected = false

    if let staticData {
      // Explicit capability flags (if provided by server/custom builds).
      let explicitTrueKeys = [
        "supportsAM",
        "supportAM",
        "amEnabled",
        "enableAM",
        "allowAM",
        "mwEnabled",
        "lwEnabled",
        "swEnabled"
      ]

      for key in explicitTrueKeys {
        if let value = staticData[key], parseBool(value) == true {
          return true
        }
      }

      // Some FM-DX instances expose server-side station presets in static_data.
      // Any preset below FM broadcast range strongly indicates AM/LW/MW/SW support.
      let presetFrequencies = parseFMDXStaticPresetFrequencies(staticData: staticData)
      if presetFrequencies.contains(where: { $0 < 64_000_000 }) {
        return true
      }

      let descriptionFields = [
        parseString(staticData["tunerDesc"]),
        parseString(staticData["tunerName"])
      ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

      for field in descriptionFields {
        if containsAMHint(field) {
          return true
        }
        if indicatesFMOnlyRange(field) {
          fmOnlyHintDetected = true
        }
      }
    }

    if let apiScript, containsFMDXAPIScriptAMSupportHint(apiScript) {
      return true
    }

    if let indexHTML, !indexHTML.isEmpty {
      if containsAMHint(indexHTML) {
        return true
      }
      if containsFMDXAPIScriptAMSupportHint(indexHTML) {
        return true
      }
      if indicatesFMOnlyRange(indexHTML) {
        fmOnlyHintDetected = true
      }
    }

    if fmOnlyHintDetected {
      return false
    }

    // FM-only is the safest fallback when server does not advertise AM capabilities.
    return false
  }

  private func parseFilterControlSupport(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    return normalized.contains("class=\"data-eq")
      || normalized.contains("class=\"data-ims")
      || normalized.contains(" data-eq ")
      || normalized.contains(" data-ims ")
  }

  private func parseAGCSupport(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    return normalized.contains("id=\"data-agc\"")
      || normalized.contains("id=\"data-agc-phone\"")
      || normalized.contains("class=\"data-agc")
      || normalized.contains(" data-agc ")
  }

  private func parseTunePasswordRequirement(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    if hasAuthenticatedFMDXTuneAccess(indexHTML: indexHTML) {
      return false
    }
    return normalized.contains("only people with tune password can tune")
      || normalized.contains("data-tooltip=\"only people with tune password can tune")
      || normalized.contains("aria-label=\"only people with tune password can tune")
      || (normalized.contains("fa-key") && normalized.contains("tune password"))
  }

  private func parseAdminLockRequirement(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    if hasAuthenticatedFMDXAdminAccess(indexHTML: indexHTML) {
      return false
    }
    return normalized.contains("tuner is currently locked to admin")
      || normalized.contains("data-tooltip=\"tuner is currently locked to admin")
      || normalized.contains("aria-label=\"tuner is currently locked to admin")
      || (normalized.contains("fa-lock") && normalized.contains("locked to admin"))
  }

  private func hasAuthenticatedFMDXTuneAccess(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    return normalized.contains("you are logged in and can control the receiver")
      || hasAuthenticatedFMDXAdminAccess(indexHTML: indexHTML)
  }

  private func hasAuthenticatedFMDXAdminAccess(indexHTML: String?) -> Bool {
    guard let indexHTML, !indexHTML.isEmpty else { return false }
    let normalized = indexHTML.lowercased()
    return normalized.contains("you are logged in as an adminstrator")
      || normalized.contains("you are logged in as an administrator")
  }

  private func parsePresetFrequencyHz(from preset: [String: Any]) -> Int? {
    let candidateKeys = ["frequencyHz", "frequency", "freq", "f"]
    for key in candidateKeys {
      guard let raw = preset[key] else { continue }
      if let value = parseDouble(raw), value.isFinite, value > 0 {
        // Frequency values below 1_000 are usually MHz, below 1_000_000 often kHz.
        if value < 1_000 {
          return Int((value * 1_000_000.0).rounded())
        }
        if value < 1_000_000 {
          return Int((value * 1_000.0).rounded())
        }
        return Int(value.rounded())
      }
    }
    return nil
  }

  func parseFMDXStaticPresetFrequencies(staticData: [String: Any]?) -> [Int] {
    guard let presets = staticData?["presets"] as? [Any] else { return [] }

    var frequencies: [Int] = []
    var seen = Set<Int>()

    for item in presets {
      let frequencyHz: Int?
      if let dictionary = item as? [String: Any] {
        frequencyHz = parsePresetFrequencyHz(from: dictionary)
      } else if let raw = parseDouble(item), raw.isFinite, raw > 0 {
        if raw < 1_000 {
          frequencyHz = Int((raw * 1_000_000.0).rounded())
        } else if raw < 1_000_000 {
          frequencyHz = Int((raw * 1_000.0).rounded())
        } else {
          frequencyHz = Int(raw.rounded())
        }
      } else {
        frequencyHz = nil
      }

      guard let normalizedFrequencyHz = frequencyHz, normalizedFrequencyHz > 0 else {
        continue
      }

      let roundedFrequencyHz = Int((Double(normalizedFrequencyHz) / 1_000.0).rounded() * 1_000.0)
      guard seen.insert(roundedFrequencyHz).inserted else { continue }
      frequencies.append(roundedFrequencyHz)
    }

    return frequencies.sorted()
  }

  func buildFMDXStaticPresetBookmarks(
    staticData: [String: Any]?,
    pluginBookmarks: [SDRServerBookmark]
  ) -> [SDRServerBookmark] {
    let staticFrequencies = parseFMDXStaticPresetFrequencies(staticData: staticData)
    guard !staticFrequencies.isEmpty else { return [] }

    let namesByFrequency = Dictionary(uniqueKeysWithValues: pluginBookmarks.map { ($0.frequencyHz, $0.name) })

    return staticFrequencies.enumerated().map { index, frequencyHz in
      let fallbackName = FrequencyFormatter.fmDxMHzText(fromHz: frequencyHz)
      let resolvedName = namesByFrequency[frequencyHz]?.trimmingCharacters(in: .whitespacesAndNewlines)
      let safeName = (resolvedName?.isEmpty == false) ? resolvedName! : fallbackName
      return SDRServerBookmark(
        id: "fmdx-station-static-\(index + 1)-\(frequencyHz)",
        name: safeName,
        frequencyHz: frequencyHz,
        modulation: .fm,
        source: "fmdx-station-list"
      )
    }
  }

  func isGenericFMDXPluginPresetList(_ bookmarks: [SDRServerBookmark]) -> Bool {
    let genericFrequencies: [Int] = [
      89_100_000,
      89_700_000,
      94_200_000,
      94_400_000,
      94_700_000,
      94_800_000,
      96_400_000,
      98_400_000,
      99_000_000,
      103_400_000,
      104_500_000,
      107_400_000
    ]
    let genericNames = Set([
      "r.piekary",
      "radio 90",
      "express fm",
      "silesia",
      "piraci slask",
      "r.fest",
      "katowice",
      "radio zet",
      "r.opole",
      "antyradio",
      "r.bielsko",
      "radio em"
    ])

    guard bookmarks.count == genericFrequencies.count else { return false }
    guard bookmarks.map(\.frequencyHz).sorted() == genericFrequencies else { return false }

    let normalizedNames = Set(
      bookmarks.map {
        $0.name
          .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
      }
    )
    return normalizedNames.intersection(genericNames).count >= 8
  }

  private func containsAMHint(_ text: String) -> Bool {
    let lowered = text.lowercased()
    let tokens = [" am ", " am/", "/am", " lw ", " mw ", " sw ", "shortwave", "medium wave", "long wave"]
    if tokens.contains(where: { lowered.contains($0) }) {
      return true
    }

    // Handle boundary cases (e.g. beginning/end of string).
    if lowered.hasPrefix("am ") || lowered.hasSuffix(" am") {
      return true
    }
    if lowered.contains("(am)") || lowered.contains("[am]") {
      return true
    }

    return false
  }

  private func containsFMDXAPIScriptAMSupportHint(_ text: String) -> Bool {
    let normalized = text
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\t", with: "")

    let markers = [
      "currentfreq<0.52",
      "currentfreq<1.71",
      "currentfreq<29.6"
    ]

    return markers.contains(where: { normalized.contains($0) })
  }

  private func indicatesFMOnlyRange(_ text: String) -> Bool {
    // Matches limits/ranges such as "64-108 MHz" or "65.0 to 108.0 MHz".
    guard let regex = try? NSRegularExpression(
      pattern: #"(?i)(?:limit|range|zakres)?[^0-9]{0,20}([0-9]{2,3}(?:[.,][0-9]+)?)\s*(?:mhz|m)?\s*(?:-|to|do)\s*([0-9]{2,3}(?:[.,][0-9]+)?)\s*(?:mhz|m)"#,
      options: []
    ) else {
      return false
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
    for match in matches {
      guard match.numberOfRanges >= 3 else { continue }
      let lowerRaw = nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
      let upperRaw = nsText.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")
      guard let lower = Double(lowerRaw), let upper = Double(upperRaw) else { continue }
      if lower >= 60, lower <= 76, upper >= 87, upper <= 120 {
        return true
      }
    }
    return false
  }

  private func refreshStationListIfNeeded(profile: SDRConnectionProfile) async {
    guard runtimePolicy.allowsVisualTelemetry else { return }
    let now = Date()
    guard now >= nextStationListRefreshAt else { return }

    let basePath = activeBasePath
    let staticData = try? await fetchStaticData(profile: profile)
    let html = try? await fetchIndexHTML(profile: profile, basePath: basePath)
    let stationList = await fetchStationListBookmarks(
      profile: profile,
      staticData: staticData,
      indexHTML: html,
      basePath: basePath
    )
    nextStationListRefreshAt = nextStationListRefreshDate(after: now, stationList: stationList)
    guard stationList != lastPublishedFMDXPresets else { return }

    lastPublishedFMDXPresets = stationList
    enqueueTelemetry(.fmdxPresets(stationList, source: lastPublishedFMDXPresetSource))
    log("FM-DX station list refreshed (\(stationList.count) entries)")
  }

  private func nextStationListRefreshDate(after now: Date, stationList: [SDRServerBookmark]) -> Date {
    if stationListUnavailable {
      return now.addingTimeInterval(30 * 60)
    }
    let interval = stationList.isEmpty ? stationListRetryInterval : stationListRefreshInterval
    return now.addingTimeInterval(interval)
  }

  private func healthLoopIntervalNanoseconds() -> UInt64 {
    switch runtimePolicy {
    case .interactive:
      return 7_000_000_000
    case .passive:
      return 10_000_000_000
    case .background:
      return 14_000_000_000
    }
  }

  private func pollIntervalNanoseconds(hasRecentRealtimeStatus: Bool) -> UInt64 {
    switch runtimePolicy {
    case .interactive:
      return hasRecentRealtimeStatus ? 12_000_000_000 : 3_500_000_000
    case .passive:
      return hasRecentRealtimeStatus ? 18_000_000_000 : 8_000_000_000
    case .background:
      return hasRecentRealtimeStatus ? 30_000_000_000 : 12_000_000_000
    }
  }

  private func fetchStationListBookmarks(
    profile: SDRConnectionProfile,
    staticData: [String: Any]?,
    indexHTML: String?,
    basePath: String
  ) async -> [SDRServerBookmark] {
    let staticBookmarksFallback = buildFMDXStaticPresetBookmarks(
      staticData: staticData,
      pluginBookmarks: []
    )

    let scriptURLs = resolveStationListScriptURLs(
      indexHTML: indexHTML,
      profile: profile,
      basePath: basePath
    )
    guard !scriptURLs.isEmpty else {
      if !staticBookmarksFallback.isEmpty {
        stationListUnavailable = false
        lastPublishedFMDXPresetSource = "static_data.presets"
        log("Loaded FM-DX station list (\(staticBookmarksFallback.count)) from static_data.presets")
        return staticBookmarksFallback
      }
      if let indexHTML, !indexHTML.isEmpty {
        stationListUnavailable = true
      }
      return []
    }

    var best: [SDRServerBookmark] = []
    var bestScore = Int.min
    var bestSource: String?
    var lastError: Error?

    if let indexHTML, !indexHTML.isEmpty {
      let inlineStationList = parseStationListBookmarks(from: indexHTML, requiresPresetMarker: true)
      if !inlineStationList.isEmpty {
        best = inlineStationList
        bestScore = FMDXPresetScriptParser.qualityScore(for: inlineStationList)
        bestSource = "inline defaultPresetData"
      }
    }

    for scriptURL in scriptURLs {
      do {
        let script = try await fetchRemoteText(url: scriptURL)
        let stationList = parseStationListBookmarks(from: script)
        guard !stationList.isEmpty else { continue }

        let score = FMDXPresetScriptParser.qualityScore(for: stationList)
        if score > bestScore {
          best = stationList
          bestScore = score
          bestSource = scriptURL.absoluteString
        }
      } catch {
        lastError = error
      }
    }

    if !best.isEmpty {
      let staticBookmarks = buildFMDXStaticPresetBookmarks(
        staticData: staticData,
        pluginBookmarks: best
      )

      if isGenericFMDXPluginPresetList(best), !staticBookmarks.isEmpty {
        stationListUnavailable = false
        lastPublishedFMDXPresetSource = "static_data.presets (generic ButtonPresets defaults ignored)"
        log("Loaded FM-DX station list (\(staticBookmarks.count)) from static_data.presets after rejecting generic plugin defaults")
        return staticBookmarks
      }

      stationListUnavailable = false
      lastPublishedFMDXPresetSource = bestSource ?? "unknown"
      log("Loaded FM-DX station list (\(best.count)) from \(bestSource ?? "unknown source")")
      return best
    }

    if !staticBookmarksFallback.isEmpty {
      stationListUnavailable = false
      lastPublishedFMDXPresetSource = "static_data.presets"
      log("Loaded FM-DX station list (\(staticBookmarksFallback.count)) from static_data.presets")
      return staticBookmarksFallback
    }

    if let lastError {
      log("Unable to load FM-DX station list: \(lastError.localizedDescription)", severity: .warning)
    }
    lastPublishedFMDXPresetSource = stationListUnavailable ? "unavailable" : "unknown"
    return []
  }

  private func resolveStationListScriptURLs(
    indexHTML: String?,
    profile: SDRConnectionProfile,
    basePath: String
  ) -> [URL] {
    var scoredURLs: [String: (url: URL, score: Int)] = [:]

    if let indexHTML, !indexHTML.isEmpty,
      let indexURL = try? makeHTTPURL(profile: profile, path: basePath) {
      let scriptPaths = captures(
        for: #"(?is)<script[^>]+src=["']([^"']+)["'][^>]*>"#,
        in: indexHTML,
        group: 1
      )

      for rawPath in scriptPaths {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { continue }
        guard let resolvedURL = URL(string: trimmedPath, relativeTo: indexURL)?.absoluteURL else { continue }

        let score = stationScriptScore(for: trimmedPath)
        guard score > 0 else { continue }
        addStationScriptCandidate(resolvedURL, score: score, to: &scoredURLs)
      }
    }

    if indexHTML == nil || indexHTML?.isEmpty == true {
      let fallbackScriptPaths: [(path: String, score: Int)] = [
        ("js/plugins/ButtonPresets/pluginButtonPresets.js", 240),
        ("js/plugins/buttonpresets/pluginbuttonpresets.js", 220),
        ("js/plugins/button-presets/plugin-button-presets.js", 190),
        ("plugins/ButtonPresets/pluginButtonPresets.js", 170),
        ("plugins/buttonpresets/pluginbuttonpresets.js", 160),
        ("js/plugins/server-list/server-list.js", 40)
      ]

      for fallback in fallbackScriptPaths {
        guard let fallbackURL = makeStationScriptURL(
          profile: profile,
          basePath: basePath,
          relativePath: fallback.path
        ) else {
          continue
        }
        addStationScriptCandidate(fallbackURL, score: fallback.score, to: &scoredURLs)
      }
    }

    return scoredURLs.values
      .sorted { lhs, rhs in
        if lhs.score == rhs.score {
          return lhs.url.absoluteString < rhs.url.absoluteString
        }
        return lhs.score > rhs.score
      }
      .prefix(8)
      .map(\.url)
  }

  private func makeStationScriptURL(
    profile: SDRConnectionProfile,
    basePath: String,
    relativePath: String
  ) -> URL? {
    let cleanedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !cleanedPath.isEmpty else { return nil }
    return try? makeHTTPURL(profile: profile, path: "\(basePath)\(cleanedPath)")
  }

  private func addStationScriptCandidate(
    _ url: URL,
    score: Int,
    to scoredURLs: inout [String: (url: URL, score: Int)]
  ) {
    let key = url.absoluteString
    if let existing = scoredURLs[key], existing.score >= score {
      return
    }
    scoredURLs[key] = (url, score)
  }

  private func stationScriptScore(for path: String) -> Int {
    let lower = path.lowercased()
    var score = 0
    if lower.contains("pluginbuttonpresets") { score += 220 }
    if lower.contains("buttonpresets") { score += 160 }
    if lower.contains("button-presets") { score += 120 }
    if lower.contains("preset") { score += 70 }
    if lower.contains("station-list") { score += 45 }
    if lower.contains("station") { score += 20 }
    if lower.contains("server-list") || lower.contains("serverlist") { score += 20 }
    if lower.contains("list") { score += 10 }
    return score
  }

  private func fetchRemoteText(url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("text/javascript,text/plain,*/*", forHTTPHeaderField: "Accept")
    request.setValue(ListenSDRNetworkIdentity.fmdxUserAgent(), forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode) else {
      throw SDRClientError.unsupported("FM-DX station list script is unavailable.")
    }

    if let text = String(data: data, encoding: .utf8), !text.isEmpty {
      return text
    }
    if let text = String(data: data, encoding: .isoLatin1), !text.isEmpty {
      return text
    }

    throw SDRClientError.unsupported("FM-DX station list script returned unreadable content.")
  }

  private func parseStationListBookmarks(
    from script: String,
    requiresPresetMarker: Bool = false
  ) -> [SDRServerBookmark] {
    FMDXPresetScriptParser.parseBookmarks(
      from: script,
      requiresPresetMarker: requiresPresetMarker,
      source: "fmdx-station-list"
    )
  }

  private func captures(for pattern: String, in text: String, group: Int) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return []
    }

    let nsText = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
    return matches.compactMap { match in
      guard match.numberOfRanges > group else { return nil }
      let range = match.range(at: group)
      guard range.location != NSNotFound else { return nil }
      return nsText.substring(with: range)
    }
  }

  private func stripHTMLTags(_ text: String) -> String {
    text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  }

  private func decodeHTMLEntities(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
  }

  private func updateStatus(from snapshot: [String: Any]) {
    let previous = latestTelemetry
    let keys = Set(snapshot.keys)

    func mergedOptional<T>(
      key: String,
      previous previousValue: T?,
      parser: (Any?) -> T?
    ) -> T? {
      if keys.contains(key) {
        return parser(snapshot[key])
      }
      return previousValue
    }

    func mergedArray<T>(
      key: String,
      previous previousValue: [T],
      parser: (Any?) -> [T]
    ) -> [T] {
      if keys.contains(key) {
        return parser(snapshot[key])
      }
      return previousValue
    }

    let telemetry = FMDXTelemetry(
      frequencyMHz: mergedOptional(key: "freq", previous: previous?.frequencyMHz, parser: parseFrequencyMHz),
      signal: mergedOptional(key: "sig", previous: previous?.signal, parser: parseDouble),
      signalTop: mergedOptional(key: "sigTop", previous: previous?.signalTop, parser: parseDouble),
      users: mergedOptional(key: "users", previous: previous?.users, parser: parseInt),
      isStereo: mergedOptional(key: "st", previous: previous?.isStereo, parser: parseBool),
      isForcedStereo: mergedOptional(key: "stForced", previous: previous?.isForcedStereo, parser: parseBool),
      rdsEnabled: mergedOptional(key: "rds", previous: previous?.rdsEnabled, parser: parseBool),
      pi: mergedOptional(key: "pi", previous: previous?.pi, parser: parseString),
      ps: mergedOptional(key: "ps", previous: previous?.ps, parser: parseString),
      rt0: mergedOptional(key: "rt0", previous: previous?.rt0, parser: parseString),
      rt1: mergedOptional(key: "rt1", previous: previous?.rt1, parser: parseString),
      pty: mergedOptional(key: "pty", previous: previous?.pty, parser: parseInt),
      tp: mergedOptional(key: "tp", previous: previous?.tp, parser: parseInt),
      ta: mergedOptional(key: "ta", previous: previous?.ta, parser: parseInt),
      ms: mergedOptional(key: "ms", previous: previous?.ms, parser: parseInt),
      ecc: mergedOptional(key: "ecc", previous: previous?.ecc, parser: parseInt),
      rbds: mergedOptional(key: "rbds", previous: previous?.rbds, parser: parseBool),
      countryName: mergedOptional(key: "country_name", previous: previous?.countryName, parser: parseString),
      countryISO: mergedOptional(key: "country_iso", previous: previous?.countryISO, parser: parseString),
      afMHz: mergedArray(key: "af", previous: previous?.afMHz ?? [], parser: parseAF),
      bandwidth: mergedOptional(key: "bw", previous: previous?.bandwidth, parser: parseString),
      antenna: mergedOptional(key: "ant", previous: previous?.antenna, parser: parseString),
      agc: mergedOptional(key: "agc", previous: previous?.agc, parser: parseString),
      eq: mergedOptional(key: "eq", previous: previous?.eq, parser: parseString),
      ims: mergedOptional(key: "ims", previous: previous?.ims, parser: parseString),
      psErrors: mergedOptional(key: "ps_errors", previous: previous?.psErrors, parser: parseString),
      rt0Errors: mergedOptional(key: "rt0_errors", previous: previous?.rt0Errors, parser: parseString),
      rt1Errors: mergedOptional(key: "rt1_errors", previous: previous?.rt1Errors, parser: parseString),
      txInfo: mergedOptional(key: "txInfo", previous: previous?.txInfo, parser: { raw in
        parseTxInfo(raw as? [String: Any])
      })
    )

    if telemetry == previous {
      return
    }
    latestTelemetry = telemetry
    enqueueTelemetry(.fmdx(telemetry))
    let summary = makeStatusSummary(from: telemetry)
    pendingStatusUpdate = summary.isEmpty ? nil : summary
  }

  private func makeStatusSummary(from telemetry: FMDXTelemetry) -> String {
    var parts: [String] = []

    if let frequencyMHz = telemetry.frequencyMHz {
      parts.append(String(format: "%.3f MHz", frequencyMHz))
    }
    if let station = telemetry.txInfo?.station, !station.isEmpty, station != "?" {
      parts.append(station)
    }
    if let ps = telemetry.ps, !ps.isEmpty, ps != "?" {
      parts.append("PS \(ps)")
    }

    return parts.joined(separator: " | ")
  }

  private func parseAF(_ value: Any?) -> [Double] {
    guard let raw = value as? [Any] else { return [] }
    return raw.compactMap { item in
      let rawValue: Double?
      if let number = item as? NSNumber {
        rawValue = number.doubleValue
      } else if let text = item as? String {
        rawValue = Double(text)
      } else {
        rawValue = nil
      }

      guard let rawValue, rawValue.isFinite, rawValue > 0 else { return nil }
      if rawValue >= 1_000_000 {
        return rawValue / 1_000_000.0
      }
      if rawValue >= 1_000 {
        return rawValue / 1_000.0
      }
      return rawValue
    }
    .sorted()
  }

  private func parseTxInfo(_ value: [String: Any]?) -> FMDXTxInfo? {
    guard let value else { return nil }
    return FMDXTxInfo(
      station: parseString(value["tx"]),
      erpKW: parseString(value["erp"]),
      city: parseString(value["city"]),
      itu: parseString(value["itu"]),
      distanceKm: parseString(value["dist"]),
      azimuthDeg: parseString(value["azi"]),
      polarization: parseString(value["pol"]),
      stationPI: parseString(value["pi"]),
      regional: parseBool(value["reg"])
    )
  }

  private func extractServerMessage(from data: Data) -> String? {
    guard
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return payload["message"] as? String
  }

  private func parseString(_ value: Any?) -> String? {
    if let text = value as? String {
      return text
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }

  private func parseDouble(_ value: Any?) -> Double? {
    if let number = value as? Double {
      return number
    }
    if let number = value as? Float {
      return Double(number)
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let text = value as? String {
      return Double(text)
    }
    return nil
  }

  private func parseFrequencyMHz(_ value: Any?) -> Double? {
    guard let raw = parseDouble(value), raw.isFinite, raw > 0 else { return nil }

    // Some FM-DX instances expose MHz (e.g. "89.100"), others kHz (e.g. 89100).
    if raw >= 1_000_000 {
      return raw / 1_000_000.0
    }
    if raw >= 1_000 {
      return raw / 1_000.0
    }
    return raw
  }

  private func parseBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.intValue != 0
    }
    if let value = value as? String {
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if ["1", "true", "yes", "on"].contains(normalized) {
        return true
      }
      if ["0", "false", "no", "off"].contains(normalized) {
        return false
      }
      if ["stereo", "enabled", "enable"].contains(normalized) {
        return true
      }
      if ["mono", "disabled", "disable"].contains(normalized) {
        return false
      }
    }
    return nil
  }

  private func parseInt(_ value: Any?) -> Int? {
    if let number = value as? Int {
      return number
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let text = value as? String {
      return Int(text)
    }
    return nil
  }

  private func enqueueTelemetry(_ event: BackendTelemetryEvent) {
    telemetryQueue.append(event)
    if telemetryQueue.count > 40 {
      telemetryQueue.removeFirst(telemetryQueue.count - 40)
    }
  }

  private func sanitizeCommandValue(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ._-")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      return nil
    }
    return trimmed
  }

  private func handleReceiveFailure(_ error: Error) {
    log("Receive loop failed: \(error.localizedDescription)", severity: .warning)
    receiveTask = nil
    socket = nil
    scheduleTextReconnect()
  }

  private func handleAudioReceiveFailure(_ error: Error) {
    log("Audio receive loop failed: \(error.localizedDescription)", severity: .warning)
    audioReceiveTask = nil
    audioSocket = nil
    FMDXMP3AudioPlayer.shared.stop()
    scheduleAudioReconnect()
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "FM-DX",
      message: message
    )
  }
}
