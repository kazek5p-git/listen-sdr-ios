import AVFAudio
import AudioToolbox
import Foundation

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
}

extension SDRBackendClient {
  func consumeStatusUpdate() async -> String? { nil }
  func consumeTelemetryUpdate() async -> BackendTelemetryEvent? { nil }
  func sendControl(_ command: BackendControlCommand) async throws {
    throw SDRClientError.unsupported("This backend does not support this control.")
  }
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

private struct ReceiverBandpass {
  let lowCut: Int
  let highCut: Int
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

private func encodeJSONString(_ payload: [String: Any]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: payload, options: [])
  guard let text = String(data: data, encoding: .utf8) else {
    throw SDRClientError.unsupported("Unable to encode JSON payload.")
  }
  return text
}

private func kiwiMode(from mode: DemodulationMode) -> String {
  switch mode {
  case .am:
    return "am"
  case .fm, .nfm:
    return "nbfm"
  case .usb:
    return "usb"
  case .lsb:
    return "lsb"
  case .cw:
    return "cw"
  }
}

private func kiwiBandpass(for mode: DemodulationMode) -> ReceiverBandpass {
  switch mode {
  case .am:
    return ReceiverBandpass(lowCut: -4900, highCut: 4900)
  case .fm:
    return ReceiverBandpass(lowCut: -6000, highCut: 6000)
  case .nfm:
    return ReceiverBandpass(lowCut: -3000, highCut: 3000)
  case .usb:
    return ReceiverBandpass(lowCut: 300, highCut: 2700)
  case .lsb:
    return ReceiverBandpass(lowCut: -2700, highCut: -300)
  case .cw:
    return ReceiverBandpass(lowCut: 300, highCut: 700)
  }
}

private func openWebRXMode(from mode: DemodulationMode) -> String {
  switch mode {
  case .am:
    return "am"
  case .fm:
    return "wfm"
  case .nfm:
    return "nfm"
  case .usb:
    return "usb"
  case .lsb:
    return "lsb"
  case .cw:
    return "cw"
  }
}

private func openWebRXBandpass(for mode: DemodulationMode) -> ReceiverBandpass {
  switch mode {
  case .am:
    return ReceiverBandpass(lowCut: -4900, highCut: 4900)
  case .fm:
    return ReceiverBandpass(lowCut: -75_000, highCut: 75_000)
  case .nfm:
    return ReceiverBandpass(lowCut: -6000, highCut: 6000)
  case .usb:
    return ReceiverBandpass(lowCut: 300, highCut: 2700)
  case .lsb:
    return ReceiverBandpass(lowCut: -2700, highCut: -300)
  case .cw:
    return ReceiverBandpass(lowCut: 300, highCut: 700)
  }
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
  private var lastTelemetryAt: Date = .distantPast
  private var latestTelemetry: KiwiTelemetry?

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let timestamp = Int(Date().timeIntervalSince1970)

    let sndURL = try makeWebSocketURL(profile: profile, path: "\(basePath)\(timestamp)/SND")
    log("Connecting audio stream: \(sndURL.absoluteString)")
    let soundTask = URLSession.shared.webSocketTask(with: sndURL)
    sndSocket = soundTask
    soundTask.resume()
    sndReceiveTask = Task { [soundTask] in
      await self.receiveLoop(task: soundTask, stream: .sound)
    }
    sndKeepAliveTask = Task { [soundTask] in
      await self.keepAliveLoop(task: soundTask)
    }

    try await sendSND("SET auth t=kiwi p=\(kiwiToken(profile.password))")
    let user = kiwiToken(profile.username)
    if !user.isEmpty {
      try await sendSND("SET ident_user=\(user)")
    }
    try await sendSND("SET compression=0")
    try await sendSND("SET keepalive")

    do {
      let wfURL = try makeWebSocketURL(profile: profile, path: "\(basePath)\(timestamp)/W/F")
      log("Connecting waterfall stream: \(wfURL.absoluteString)")
      let waterfallTask = URLSession.shared.webSocketTask(with: wfURL)
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
      try await sendWF("SET zoom=0 cf=0")
      try await sendWF("SET keepalive")
    } catch {
      log("Waterfall stream unavailable: \(error.localizedDescription)", severity: .warning)
    }

    log("Connection initialized")
  }

  func disconnect() async {
    sndReceiveTask?.cancel()
    sndReceiveTask = nil
    wfReceiveTask?.cancel()
    wfReceiveTask = nil

    sndKeepAliveTask?.cancel()
    sndKeepAliveTask = nil
    wfKeepAliveTask?.cancel()
    wfKeepAliveTask = nil

    sndSocket?.cancel(with: .normalClosure, reason: nil)
    sndSocket = nil
    wfSocket?.cancel(with: .normalClosure, reason: nil)
    wfSocket = nil

    lastServerMessage = nil
    pendingStatusUpdate = nil
    sampleRateHz = 12_000
    adpcmDecoder.reset()
    latestRSSI = nil
    latestWaterfallBins = []
    telemetryQueue.removeAll()
    lastTelemetryAt = .distantPast
    latestTelemetry = nil

    await MainActor.run {
      SharedAudioOutput.engine.stop()
    }
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard sndSocket != nil else { throw SDRClientError.notConnected }

    let mode = kiwiMode(from: settings.mode)
    let passband = kiwiBandpass(for: settings.mode)
    let frequencyKHz = Double(settings.frequencyHz) / 1000.0
    let formattedFrequency = String(format: "%.3f", frequencyKHz)

    try await sendSND(
      "SET mod=\(mode) low_cut=\(passband.lowCut) high_cut=\(passband.highCut) freq=\(formattedFrequency)"
    )
    try? await sendWF("SET zoom=0 cf=\(formattedFrequency)")
    log("Applied tuning: mode=\(mode) freq=\(formattedFrequency) kHz")

    if settings.agcEnabled {
      try await sendSND("SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50")
    } else {
      let manualGain = Int(settings.rfGain.rounded())
      try await sendSND("SET agc=0 hang=0 thresh=-100 slope=6 decay=1000 manGain=\(manualGain)")
    }

    let squelchEnabled = settings.squelchEnabled ? 1 : 0
    let squelchThreshold = settings.squelchEnabled ? 6 : 0
    try await sendSND("SET squelch=\(squelchEnabled) max=\(squelchThreshold)")
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
      lastServerMessage = text
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

      case "badp":
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
          pendingStatusUpdate = message
          log("Waterfall stream authentication failed: \(message)", severity: .warning)
        }

      case "too_busy":
        let message = "KiwiSDR is currently busy (all client slots are used)."
        if stream == .sound {
          lastServerMessage = message
        } else {
          pendingStatusUpdate = message
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

    if isStereo {
      return
    }

    let audioBytes = Data(body.dropFirst(7))
    guard !audioBytes.isEmpty else { return }

    let pcm: [Int16]
    if isCompressed {
      pcm = adpcmDecoder.decode(audioBytes)
    } else {
      pcm = decodeInt16PCM(audioBytes, littleEndian: isLittleEndian)
    }

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }

    let sampleRate = Double(sampleRateHz)
    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func handleKiwiWaterfall(_ body: Data) async {
    var payload = body
    guard !payload.isEmpty else { return }
    payload.removeFirst() // protocol header byte used by Kiwi W/F stream
    guard payload.count > 12 else { return }

    let bins = Array(payload.dropFirst(12))
    guard !bins.isEmpty else { return }

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
      sampleRateHz: sampleRateHz
    )
    if telemetry == latestTelemetry {
      return
    }
    latestTelemetry = telemetry
    enqueueTelemetry(.kiwi(telemetry))
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
      lastServerMessage = error.localizedDescription
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
  private var lastAppliedSettings: RadioSessionSettings = .default
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
  private var lastReportedFrequencyHz: Int?
  private var lastReportedMode: DemodulationMode?

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let wsPath = "\(basePath)ws/"
    let url = try makeWebSocketURL(profile: profile, path: wsPath)
    log("Connecting to \(url.absoluteString)")

    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }

    try await send("SERVER DE CLIENT client=ListenSDR type=receiver")
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
    lastReportedFrequencyHz = nil
    lastReportedMode = nil

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
    default:
      throw SDRClientError.unsupported("OpenWebRX does not support this control.")
    }
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func openWebRXParams(from settings: RadioSessionSettings) -> [String: Any] {
    let mode = openWebRXMode(from: settings.mode)
    let passband = openWebRXBandpass(for: settings.mode)
    let offset = boundedOpenWebRXOffset(for: settings.frequencyHz)

    return [
      "mod": mode,
      "offset_freq": offset,
      "low_cut": passband.lowCut,
      "high_cut": passband.highCut,
      "squelch_level": settings.squelchEnabled ? -95 : -150
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

        if centerChanged {
          try? await sendJSON(
            [
              "type": "dspcontrol",
              "params": openWebRXParams(from: lastAppliedSettings)
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
      if let value = parsed["value"] as? [[String: Any]] {
        serverBookmarks = parseBookmarks(from: value, source: "server")
        emitBookmarks()
      }

    case "dial_frequencies":
      if let value = parsed["value"] as? [[String: Any]] {
        dialBookmarks = parseBookmarks(from: value, source: "dial")
        emitBookmarks()
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
      await playAudio(payload, sampleRate: Double(outputRateHz))

    case 4:
      await playAudio(payload, sampleRate: Double(hdOutputRateHz))

    default:
      break
    }
  }

  private func playAudio(_ payload: Data, sampleRate: Double) async {
    guard !payload.isEmpty else { return }

    let pcm: [Int16]
    if audioCompression.lowercased() == "adpcm" {
      pcm = adpcmDecoder.decodeWithSync(payload)
    } else {
      pcm = decodeInt16PCM(payload, littleEndian: true)
    }

    let floats = int16ToFloatPCM(pcm)
    guard !floats.isEmpty else { return }

    await MainActor.run {
      SharedAudioOutput.engine.enqueueMono(samples: floats, sampleRate: sampleRate)
    }
  }

  private func extractInt(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let text = value as? String, let intValue = Int(text) {
      return intValue
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

  private func extractOpenWebRXTunedFrequency(from payload: [String: Any]) -> Int? {
    if let startFrequency = extractInt(payload["start_freq"]), startFrequency > 0 {
      return startFrequency
    }

    let resolvedCenterFrequency: Int? = {
      if let centerFrequency = extractInt(payload["center_freq"]), centerFrequency > 0 {
        return centerFrequency
      }
      return centerFrequencyHz
    }()

    if let center = resolvedCenterFrequency, let offset = extractInt(payload["offset_freq"]) {
      return center + offset
    }
    if let center = resolvedCenterFrequency, let startOffset = extractInt(payload["start_offset_freq"]) {
      return center + startOffset
    }
    return nil
  }

  private func emitOpenWebRXTuning(frequencyHz: Int, mode: DemodulationMode?) {
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
      request.setValue("ListenSDR/1.0", forHTTPHeaderField: "User-Agent")
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

      enqueueTelemetry(.openWebRXBandPlan(entries))
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

final class FMDXMP3AudioPlayer {
  static let shared = FMDXMP3AudioPlayer()

  private let workerQueue = DispatchQueue(label: "ListenSDR.FMDXMP3AudioPlayer")
  private let queueBufferSize: Int = 64 * 1024
  private let queueBufferCount: Int = 36
  private let maxPacketsPerBuffer: Int = 1024
  private let minEnqueueBytes: Int = 8 * 1024
  private let maxBufferHoldSeconds: TimeInterval = 0.2
  private let minBuffersBeforeStart = 4
  private let maxConsecutiveBufferStarvation = 120

  private var fileStreamID: AudioFileStreamID?
  private var audioQueue: AudioQueueRef?
  private var streamDescription: AudioStreamBasicDescription?
  private var reusableBuffers: [AudioQueueBufferRef] = []
  private var activeBuffer: AudioQueueBufferRef?
  private var activeBufferOffset = 0
  private var activePacketCount = 0
  private var activeBufferStartedAt = Date.distantPast
  private var packetDescriptions: [AudioStreamPacketDescription]
  private var queueStarted = false
  private var parserNeedsDiscontinuity = true
  private var consecutiveParseErrors = 0
  private var droppedPacketCount = 0
  private var consecutiveBufferStarvation = 0
  private var lastSuccessfulEnqueueAt = Date.distantPast
  private var enqueuedBuffersBeforeStart = 0

  private var desiredVolume: Float = 0.85
  private var muted = false

  private init() {
    packetDescriptions = Array(
      repeating: AudioStreamPacketDescription(),
      count: maxPacketsPerBuffer
    )
  }

  func append(_ data: Data) {
    guard !data.isEmpty else { return }

    workerQueue.async {
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

  func secondsSinceLastAudioOutput() -> TimeInterval {
    workerQueue.sync {
      Date().timeIntervalSince(lastSuccessfulEnqueueAt)
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
    do {
      try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
      try session.setPreferredIOBufferDuration(0.01)
      try session.setPreferredSampleRate(sampleRate)
      try session.setActive(true, options: [])
    } catch {
      log("Audio session setup failed: \(error.localizedDescription)", severity: .warning)
    }
  }

  private func applyVolumeLocked() {
    guard let audioQueue else { return }
    _ = AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, muted ? 0 : desiredVolume)
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
    activeBufferStartedAt = .distantPast
    queueStarted = false
    consecutiveParseErrors = 0
    droppedPacketCount = 0
    consecutiveBufferStarvation = 0
    lastSuccessfulEnqueueAt = .distantPast
    enqueuedBuffersBeforeStart = 0
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
      activeBufferStartedAt = Date()
    }

    guard let activeBuffer = self.activeBuffer else { return }
    let destination = activeBuffer.pointee.mAudioData.advanced(by: activeBufferOffset)
    memcpy(destination, packetData, packetSize)

    packetDescriptions[activePacketCount] = AudioStreamPacketDescription(
      mStartOffset: Int64(activeBufferOffset),
      mVariableFramesInPacket: 0,
      mDataByteSize: UInt32(packetSize)
    )
    activeBufferOffset += packetSize
    activePacketCount += 1
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
    if activeBufferOffset >= minEnqueueBytes || heldForSeconds >= maxBufferHoldSeconds {
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

      if !queueStarted {
        enqueuedBuffersBeforeStart += 1
        if enqueuedBuffersBeforeStart >= minBuffersBeforeStart {
          let startStatus = AudioQueueStart(audioQueue, nil)
          if startStatus == noErr {
            queueStarted = true
            log("FM-DX audio queue started with \(enqueuedBuffersBeforeStart) prebuffered chunks")
          } else {
            log("Unable to start audio queue (status \(startStatus))", severity: .warning)
          }
        }
      }
    } else {
      reusableBuffers.append(activeBuffer)
      consecutiveBufferStarvation += 1
      log("Unable to enqueue audio packet (status \(status))", severity: .warning)
    }

    self.activeBuffer = nil
    activeBufferOffset = 0
    activePacketCount = 0
  }

  private func recycleBuffer(_ buffer: AudioQueueBufferRef) {
    workerQueue.async {
      guard self.audioQueue != nil else { return }
      self.reusableBuffers.append(buffer)
      self.consecutiveBufferStarvation = 0
    }
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "FM-DX Audio",
      message: message
    )
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
  private var lastAudioPacketAt = Date.distantPast
  private var supportsPingEndpoint: Bool?
  private var consecutivePingFailures = 0
  private var lastRealtimeStatusAt = Date.distantPast

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()
    try await authenticateIfNeeded(profile: profile)

    activeProfile = profile
    activeBasePath = pathWithTrailingSlash(profile.normalizedPath)
    lastAppliedSettings = nil
    supportsPingEndpoint = nil
    consecutivePingFailures = 0
    lastAudioPacketAt = .distantPast
    lastRealtimeStatusAt = .distantPast

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
    let capabilities = buildCapabilities(staticData: staticData, indexHTML: html)
    if !capabilities.antennas.isEmpty || !capabilities.bandwidths.isEmpty {
      enqueueTelemetry(.fmdxCapabilities(capabilities))
    }
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
    lastAudioPacketAt = .distantPast
    lastRealtimeStatusAt = .distantPast
    supportsPingEndpoint = nil
    consecutivePingFailures = 0

    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }
    lastAppliedSettings = settings

    try await sendFrequency(settings.frequencyHz)
    try await sendFilter(eqEnabled: settings.noiseReductionEnabled, imsEnabled: settings.imsEnabled)
    try? await send("A\(settings.agcEnabled ? 1 : 0)")

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

  func sendControl(_ command: BackendControlCommand) async throws {
    switch command {
    case .selectOpenWebRXProfile:
      throw SDRClientError.unsupported("FM-DX does not support OpenWebRX profile selection.")

    case .setFMDXFrequencyHz(let frequencyHz):
      try await sendFrequency(frequencyHz)

    case .setFMDXFilter(let eqEnabled, let imsEnabled):
      try await sendFilter(eqEnabled: eqEnabled, imsEnabled: imsEnabled)

    case .setFMDXAGC(let enabled):
      try await send("A\(enabled ? 1 : 0)")

    case .setFMDXForcedStereo(let enabled):
      try await send("B\(enabled ? 1 : 0)")

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

    let task = URLSession.shared.webSocketTask(with: audioURL)
    audioSocket = task
    task.resume()

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

    let task = URLSession.shared.webSocketTask(with: url)
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
          FMDXMP3AudioPlayer.shared.append(data)
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
      try? await Task.sleep(nanoseconds: 7_000_000_000)
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
        if lastAudioPacketAt != .distantPast {
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
      let pollIntervalNs: UInt64 = hasRecentRealtimeStatus ? 12_000_000_000 : 3_500_000_000
      try? await Task.sleep(nanoseconds: pollIntervalNs)
      if Task.isCancelled {
        return
      }

      do {
        let snapshot = try await fetchAPI(profile: profile)
        updateStatus(from: snapshot)
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
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(
      withJSONObject: ["password": password],
      options: []
    )

    let (data, response) = try await URLSession.shared.data(for: request)
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
    let (data, response) = try await URLSession.shared.data(from: url)

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
    let (data, response) = try await URLSession.shared.data(from: url)

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
    request.setValue("ListenSDR/1.0", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let html = String(data: data, encoding: .utf8) else {
      throw SDRClientError.unsupported("FM-DX index page is unavailable.")
    }

    return html
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

      let (_, response) = try await URLSession.shared.data(for: request)
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
    pendingStatusUpdate = reason
    receiveTask?.cancel()
    receiveTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    scheduleTextReconnect()
  }

  private func restartAudioConnection(reason: String) {
    guard activeProfile != nil else { return }
    pendingStatusUpdate = reason
    audioReceiveTask?.cancel()
    audioReceiveTask = nil
    audioSocket?.cancel(with: .goingAway, reason: nil)
    audioSocket = nil
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
    indexHTML: String?
  ) -> FMDXCapabilities {
    let antennas = parseAntennaOptions(from: staticData)
    let bandwidths = parseBandwidthOptions(from: indexHTML)
    return FMDXCapabilities(antennas: antennas, bandwidths: bandwidths)
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
    if let signal = telemetry.signal {
      parts.append(String(format: "S %.1f", signal))
    }
    if let users = telemetry.users {
      parts.append("U \(users)")
    }
    if let countryISO = telemetry.countryISO, !countryISO.isEmpty, countryISO != "UN" {
      parts.append(countryISO)
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
