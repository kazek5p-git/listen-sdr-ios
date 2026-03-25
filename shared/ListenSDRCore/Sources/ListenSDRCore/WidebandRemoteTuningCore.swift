public struct WidebandRemoteTuningState: Codable, Equatable, Sendable {
  public let frequencyHz: Int
  public let mode: DemodulationMode
  public let preferredTuneStepHz: Int
  public let tuneStepHz: Int
  public let tuneStepPreferenceMode: TuneStepPreferenceMode

  public init(
    frequencyHz: Int,
    mode: DemodulationMode,
    preferredTuneStepHz: Int,
    tuneStepHz: Int,
    tuneStepPreferenceMode: TuneStepPreferenceMode
  ) {
    self.frequencyHz = frequencyHz
    self.mode = mode
    self.preferredTuneStepHz = preferredTuneStepHz
    self.tuneStepHz = tuneStepHz
    self.tuneStepPreferenceMode = tuneStepPreferenceMode
  }
}

public struct WidebandRemoteTuningResult: Codable, Equatable, Sendable {
  public let state: WidebandRemoteTuningState
  public let statusSummary: String
  public let normalizedBandName: String?
  public let resolvedKiwiPassband: ReceiverBandpass?

  public init(
    state: WidebandRemoteTuningState,
    statusSummary: String,
    normalizedBandName: String?,
    resolvedKiwiPassband: ReceiverBandpass?
  ) {
    self.state = state
    self.statusSummary = statusSummary
    self.normalizedBandName = normalizedBandName
    self.resolvedKiwiPassband = resolvedKiwiPassband
  }
}

public enum WidebandRemoteTuningCore {
  public static func synchronizeOpenWebRX(
    state: WidebandRemoteTuningState,
    reportedFrequencyHz: Int,
    reportedMode: DemodulationMode?,
    bandName: String?,
    bandTags: [String]
  ) -> WidebandRemoteTuningResult {
    let resolvedMode = reportedMode ?? state.mode
    let normalizedFrequencyHz = SessionFrequencyCore.normalizedFrequencyHz(
      reportedFrequencyHz,
      backend: .openWebRX,
      mode: resolvedMode
    )
    let normalizedBandName = BackendStatusSummaryCore.normalizedBandName(bandName)
    let tuneStepState = SessionTuningCore.tuneStepState(
      preferredStepHz: state.preferredTuneStepHz,
      preferenceMode: state.tuneStepPreferenceMode,
      context: BandTuningContext(
        backend: .openWebRX,
        frequencyHz: normalizedFrequencyHz,
        mode: resolvedMode,
        bandName: normalizedBandName,
        bandTags: bandTags
      )
    )

    return WidebandRemoteTuningResult(
      state: WidebandRemoteTuningState(
        frequencyHz: normalizedFrequencyHz,
        mode: resolvedMode,
        preferredTuneStepHz: tuneStepState.preferredTuneStepHz,
        tuneStepHz: tuneStepState.tuneStepHz,
        tuneStepPreferenceMode: tuneStepState.preferenceMode
      ),
      statusSummary: BackendStatusSummaryCore.openWebRXSummary(
        frequencyHz: normalizedFrequencyHz,
        mode: reportedMode,
        bandName: normalizedBandName
      ),
      normalizedBandName: normalizedBandName,
      resolvedKiwiPassband: nil
    )
  }

  public static func synchronizeKiwi(
    state: WidebandRemoteTuningState,
    reportedFrequencyHz: Int,
    reportedMode: DemodulationMode?,
    reportedBandName: String?,
    currentPassband: ReceiverBandpass,
    reportedPassband: ReceiverBandpass?,
    sampleRateHz: Int?
  ) -> WidebandRemoteTuningResult {
    let resolvedMode = reportedMode ?? state.mode
    let normalizedFrequencyHz = SessionFrequencyCore.normalizedFrequencyHz(
      reportedFrequencyHz,
      backend: .kiwiSDR,
      mode: resolvedMode
    )
    let normalizedBandName = BackendStatusSummaryCore.normalizedBandName(reportedBandName)
    let tuneStepState = SessionTuningCore.tuneStepState(
      preferredStepHz: state.preferredTuneStepHz,
      preferenceMode: state.tuneStepPreferenceMode,
      context: BandTuningContext(
        backend: .kiwiSDR,
        frequencyHz: normalizedFrequencyHz,
        mode: resolvedMode,
        bandName: normalizedBandName ?? SessionTuningCore.inferredKiwiBandName(for: normalizedFrequencyHz),
        bandTags: []
      )
    )
    let resolvedPassband = KiwiPassbandCore.normalizedBandpass(
      reportedPassband ?? currentPassband,
      mode: resolvedMode,
      sampleRateHz: sampleRateHz
    )

    return WidebandRemoteTuningResult(
      state: WidebandRemoteTuningState(
        frequencyHz: normalizedFrequencyHz,
        mode: resolvedMode,
        preferredTuneStepHz: tuneStepState.preferredTuneStepHz,
        tuneStepHz: tuneStepState.tuneStepHz,
        tuneStepPreferenceMode: tuneStepState.preferenceMode
      ),
      statusSummary: BackendStatusSummaryCore.kiwiSummary(
        frequencyHz: normalizedFrequencyHz,
        mode: reportedMode,
        reportedBandName: reportedBandName
      ),
      normalizedBandName: normalizedBandName,
      resolvedKiwiPassband: resolvedPassband
    )
  }
}
