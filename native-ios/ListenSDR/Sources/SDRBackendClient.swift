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
  private var adpcmDecoder = KiwiIMAADPCMDecoder()
  private var sampleRateHz = 12_000

  private var telemetryQueue: [BackendTelemetryEvent] = []
  private var latestRSSI: Double?
  private var latestWaterfallBins: [UInt8] = []
  private var lastTelemetryAt: Date = .distantPast

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
    sampleRateHz = 12_000
    adpcmDecoder.reset()
    latestRSSI = nil
    latestWaterfallBins = []
    telemetryQueue.removeAll()
    lastTelemetryAt = .distantPast

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
      try? await Task.sleep(nanoseconds: 1_000_000_000)
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
      await handleKiwiMessage(text)

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

  private func handleKiwiMessage(_ payload: String) async {
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
        if let value {
          lastServerMessage = kiwiAuthenticationErrorDescription(code: value)
        } else {
          lastServerMessage = "Authentication rejected by KiwiSDR."
        }
        log(lastServerMessage ?? "Authentication rejected", severity: .error)

      case "too_busy":
        lastServerMessage = "KiwiSDR is currently busy (all client slots are used)."
        log(lastServerMessage ?? "Server busy", severity: .warning)

      case "down":
        lastServerMessage = "KiwiSDR reports that the receiver is down."
        log(lastServerMessage ?? "Receiver down", severity: .warning)

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
    if !force, now.timeIntervalSince(lastTelemetryAt) < 0.25 {
      return
    }
    lastTelemetryAt = now

    let telemetry = KiwiTelemetry(
      rssiDBm: latestRSSI,
      waterfallBins: latestWaterfallBins,
      sampleRateHz: sampleRateHz
    )
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
  private var lastAppliedSettings: RadioSessionSettings = .default
  private var lastServerMessage: String?
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
    try? await sendJSON(
      [
        "type": "dspcontrol",
        "params": [
          "audio_compression": "none"
        ]
      ]
    )
    log("Requested uncompressed audio")

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
    lastServerMessage = nil
    audioCompression = "none"
    outputRateHz = 12_000
    hdOutputRateHz = 48_000
    adpcmDecoder.reset()
    telemetryQueue.removeAll()
    knownProfiles = []
    selectedProfileID = nil
    serverBookmarks = []
    dialBookmarks = []

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
    }
  }

  func isConnected() async -> Bool {
    socket != nil
  }

  private func openWebRXParams(from settings: RadioSessionSettings) -> [String: Any] {
    let mode = openWebRXMode(from: settings.mode)
    let passband = openWebRXBandpass(for: settings.mode)
    let offset = centerFrequencyHz.map { settings.frequencyHz - $0 } ?? 0

    return [
      "mod": mode,
      "offset_freq": offset,
      "low_cut": passband.lowCut,
      "high_cut": passband.highCut,
      "squelch_level": settings.squelchEnabled ? -95 : -150
    ]
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
      guard let value = parsed["value"] as? [String: Any] else { return }

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

actor FMDXWebserverClient: SDRBackendClient {
  let backend: SDRBackend = .fmDxWebserver

  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var pollTask: Task<Void, Never>?
  private var lastServerMessage: String?
  private var pendingStatusUpdate: String?
  private var telemetryQueue: [BackendTelemetryEvent] = []

  func connect(profile: SDRConnectionProfile) async throws {
    _ = try validate(profile: profile)
    await disconnect()
    try await authenticateIfNeeded(profile: profile)

    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeWebSocketURL(profile: profile, path: "\(basePath)text")
    log("Connecting to \(url.absoluteString)")

    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()

    receiveTask = Task { [task] in
      await self.receiveLoop(task: task)
    }

    pollTask = Task { [profile] in
      await self.pollLoop(profile: profile)
    }

    if let tunerName = try? await fetchTunerName(profile: profile), !tunerName.isEmpty {
      pendingStatusUpdate = "Tuner: \(tunerName)"
    }
  }

  func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil

    pollTask?.cancel()
    pollTask = nil

    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    lastServerMessage = nil
    pendingStatusUpdate = nil
    telemetryQueue.removeAll()
    log("Disconnected")
  }

  func apply(settings: RadioSessionSettings) async throws {
    guard socket != nil else { throw SDRClientError.notConnected }

    let frequencyKHz = max(1, settings.frequencyHz / 1000)
    try await send("T\(frequencyKHz)")

    // FM-DX exposes cEQ/iMS via Gxy command; map app DSP toggles to it.
    let eq = settings.noiseReductionEnabled ? 1 : 0
    let ims = settings.agcEnabled ? 1 : 0
    try? await send("G\(eq)\(ims)")

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

  func isConnected() async -> Bool {
    socket != nil
  }

  private func send(_ message: String) async throws {
    guard let socket else { throw SDRClientError.notConnected }
    try await socket.send(.string(message))
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

  private func pollLoop(profile: SDRConnectionProfile) async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
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

    updateStatus(from: snapshot)
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

  private func fetchTunerName(profile: SDRConnectionProfile) async throws -> String {
    let basePath = pathWithTrailingSlash(profile.normalizedPath)
    let url = try makeHTTPURL(profile: profile, path: "\(basePath)static_data")
    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ""
    }

    return (payload["tunerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private func updateStatus(from snapshot: [String: Any]) {
    let txInfoRaw = snapshot["txInfo"] as? [String: Any]
    let telemetry = FMDXTelemetry(
      frequencyMHz: parseDouble(snapshot["freq"]),
      signal: parseDouble(snapshot["sig"]),
      signalTop: parseDouble(snapshot["sigTop"]),
      users: parseInt(snapshot["users"]),
      isStereo: parseBool(snapshot["st"]),
      isForcedStereo: parseBool(snapshot["stForced"]),
      rdsEnabled: parseBool(snapshot["rds"]),
      pi: parseString(snapshot["pi"]),
      ps: parseString(snapshot["ps"]),
      rt0: parseString(snapshot["rt0"]),
      rt1: parseString(snapshot["rt1"]),
      pty: parseInt(snapshot["pty"]),
      tp: parseInt(snapshot["tp"]),
      ta: parseInt(snapshot["ta"]),
      countryName: parseString(snapshot["country_name"]),
      countryISO: parseString(snapshot["country_iso"]),
      afMHz: parseAF(snapshot["af"]),
      bandwidth: parseString(snapshot["bw"]),
      antenna: parseString(snapshot["ant"]),
      eq: parseString(snapshot["eq"]),
      ims: parseString(snapshot["ims"]),
      txInfo: parseTxInfo(txInfoRaw)
    )

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
      if let number = item as? NSNumber {
        return number.doubleValue / 1000.0
      }
      if let text = item as? String, let parsed = Double(text) {
        return parsed / 1000.0
      }
      return nil
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

  private func handleReceiveFailure(_ error: Error) {
    lastServerMessage = error.localizedDescription
    log("Receive loop failed: \(error.localizedDescription)", severity: .error)
    receiveTask = nil
    socket = nil
  }

  private func log(_ message: String, severity: DiagnosticSeverity = .info) {
    Diagnostics.log(
      severity: severity,
      category: "FM-DX",
      message: message
    )
  }
}
