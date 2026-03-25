import Foundation
import XCTest
@testable import ListenSDRCore

enum FixtureLoader {
  static func load<T: Decodable>(_ filename: String, as type: T.Type = T.self) throws -> T {
    guard let url = Bundle.module.url(
      forResource: filename,
      withExtension: nil,
      subdirectory: "Fixtures"
    ) else {
      XCTFail("Missing fixture: \(filename)")
      throw FixtureError.missingFixture(filename)
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(T.self, from: data)
  }
}

enum FixtureError: Error {
  case missingFixture(String)
  case invalidFixtureValue(String)
}

struct FrequencyInputParserFixtureSet: Decodable {
  let cases: [Case]

  struct Case: Decodable {
    let label: String
    let text: String
    let context: String
    let preferredRangeHz: IntRangeFixture?
    let expectedHz: Int?
  }
}

struct FrequencyFormatterFixtureSet: Decodable {
  let mhzTextCases: [Case]
  let tuneStepTextCases: [Case]

  struct Case: Decodable {
    let label: String
    let hz: Int
    let expected: String
  }
}

struct ReceiverLinkImportFixtureSet: Decodable {
  let normalizedURLCases: [NormalizedURLCase]
  let normalizeInspectableURLCases: [NormalizeInspectableURLCase]
  let backendDetectionCases: [BackendDetectionCase]
  let normalizedProfilePathCases: [NormalizedProfilePathCase]
  let preferredTitleCases: [PreferredTitleCase]
  let fallbackDisplayNameCases: [FallbackDisplayNameCase]

  struct NormalizedURLCase: Decodable {
    let label: String
    let input: String
    let expected: URLFixture?
    let expectedError: String?
  }

  struct NormalizeInspectableURLCase: Decodable {
    let label: String
    let input: URLFixture
    let expected: URLFixture
  }

  struct BackendDetectionCase: Decodable {
    let label: String
    let urlPath: String
    let html: String
    let expectedBackend: String?
    let expectedError: String?
  }

  struct NormalizedProfilePathCase: Decodable {
    let label: String
    let backend: String
    let rawPath: String
    let expectedPath: String
  }

  struct PreferredTitleCase: Decodable {
    let label: String
    let html: String
    let expectedTitle: String?
  }

  struct FallbackDisplayNameCase: Decodable {
    let label: String
    let host: String?
    let expectedName: String
  }
}

struct ReceiverIdentityFixtureSet: Decodable {
  let cases: [Case]

  struct Case: Decodable {
    let label: String
    let backend: String
    let host: String
    let port: Int
    let useTLS: Bool
    let path: String
    let expectedKey: String
  }
}

struct ReceiverDirectoryParsingFixtureSet: Decodable {
  let receiverbookJsonCases: [ReceiverbookJSONCase]
  let endpointCases: [EndpointCase]
  let fmdxStatusCases: [StatusCase]
  let receiverbookTypeCases: [ReceiverbookTypeCase]
  let probeStatusCases: [ProbeStatusCase]

  struct ReceiverbookJSONCase: Decodable {
    let label: String
    let html: String
    let expectedJSON: String?
    let expectedError: String?
  }

  struct EndpointCase: Decodable {
    let label: String
    let input: String?
    let expected: ReceiverDirectoryEndpointFixture?
  }

  struct StatusCase: Decodable {
    let label: String
    let rawValue: Int?
    let expected: String
  }

  struct ReceiverbookTypeCase: Decodable {
    let label: String
    let value: String
    let backend: String
    let expected: Bool
  }

  struct ProbeStatusCase: Decodable {
    let label: String
    let statusCode: Int
    let expected: String
  }
}

struct ReceiverCountryResolverFixtureSet: Decodable {
  let countryCodeCases: [CountryCodeCase]
  let countryNameCases: [CountryNameCase]
  let metadataCases: [MetadataCase]

  struct CountryCodeCase: Decodable {
    let label: String
    let countryCode: String?
    let countryName: String?
    let expectedCode: String?
  }

  struct CountryNameCase: Decodable {
    let label: String
    let rawValue: String?
    let expectedCode: String?
  }

  struct MetadataCase: Decodable {
    let label: String
    let locationLabel: String?
    let host: String?
    let expectedCode: String?
  }
}

struct ReceiverDirectorySearchFixtureSet: Decodable {
  let normalizedSearchTextCases: [NormalizedSearchTextCase]
  let searchableTextCases: [SearchableTextCase]
  let matchCases: [MatchCase]

  struct NormalizedSearchTextCase: Decodable {
    let label: String
    let input: String
    let expected: String
  }

  struct SearchableTextCase: Decodable {
    let label: String
    let fields: [String?]
    let expected: String
  }

  struct MatchCase: Decodable {
    let label: String
    let query: String
    let searchableText: String
    let expected: Bool
  }
}

struct ReceiverDirectorySelectionFixtureSet: Decodable {
  let countryOptionCases: [CountryOptionCase]
  let deduplicatedCases: [DeduplicatedCase]
  let filteredCases: [FilteredCase]

  struct Entry: Decodable {
    let id: String
    let backend: String
    let name: String
    let sourceName: String
    let status: String
    let countryLabel: String?
    let locationLabel: String?
    let searchableText: String
    let detailText: String
    let receiverIdentity: String
  }

  struct CountryOptionCase: Decodable {
    let label: String
    let backend: String
    let sortOption: String
    let entries: [Entry]
    let expected: [CountryOption]
  }

  struct CountryOption: Decodable {
    let countryLabel: String
    let receiverCount: Int
  }

  struct DeduplicatedCase: Decodable {
    let label: String
    let entries: [Entry]
    let expectedOrder: [String]
    let expectedStatuses: [String]
    let expectedDetailTexts: [String]
  }

  struct FilteredCase: Decodable {
    let label: String
    let backend: String
    let searchText: String
    let statusFilter: String
    let sortOption: String
    let selectedCountry: String
    let favoritesOnly: Bool
    let favoriteReceiverIDs: [String]
    let entries: [Entry]
    let expectedOrder: [String]
  }
}

struct BandTuningCoreFixtureSet: Decodable {
  let profileCases: [ProfileCase]
  let kiwiBandNameCases: [KiwiBandNameCase]

  struct ProfileCase: Decodable {
    let label: String
    let context: Context
    let expectedProfile: ExpectedProfile
    let expectedAutomaticTuneStepHz: Int
    let manualPreferredTuneStepHz: Int
    let expectedManualTuneStepHz: Int
  }

  struct Context: Decodable {
    let backend: String
    let frequencyHz: Int
    let mode: String
    let bandName: String?
    let bandTags: [String]
  }

  struct ExpectedProfile: Decodable {
    let id: String
    let stepOptionsHz: [Int]
    let defaultStepHz: Int
  }

  struct KiwiBandNameCase: Decodable {
    let label: String
    let frequencyHz: Int
    let expectedBandName: String?
  }
}

struct SessionFrequencyCoreFixtureSet: Decodable {
  let normalizedFrequencyCases: [NormalizedFrequencyCase]
  let tunedFrequencyCases: [TunedFrequencyCase]

  struct NormalizedFrequencyCase: Decodable {
    let label: String
    let backend: String?
    let mode: String
    let inputFrequencyHz: Int
    let expectedFrequencyHz: Int
  }

  struct TunedFrequencyCase: Decodable {
    let label: String
    let backend: String?
    let mode: String
    let currentFrequencyHz: Int
    let tuneStepHz: Int
    let stepCount: Int
    let expectedFrequencyHz: Int
  }
}

struct SessionTuneStepStateFixtureSet: Decodable {
  let stateCases: [StateCase]
  let manualSelectionCases: [ManualSelectionCase]

  struct StateCase: Decodable {
    let label: String
    let preferredStepHz: Int
    let preferenceMode: String
    let context: BandTuningCoreFixtureSet.Context?
    let expectedTuneStepHz: Int
    let expectedPreferredTuneStepHz: Int
  }

  struct ManualSelectionCase: Decodable {
    let label: String
    let requestedStepHz: Int
    let context: BandTuningCoreFixtureSet.Context?
    let expectedTuneStepHz: Int
    let expectedPreferredTuneStepHz: Int
  }
}

struct FMDXSessionCoreFixtureSet: Decodable {
  let quickBandCases: [QuickBandCase]
  let inferredModeCases: [InferredModeCase]
  let preferredFrequencyCases: [PreferredFrequencyCase]
  let rememberCases: [RememberCase]
  let seedCases: [SeedCase]
  let normalizedReportedFrequencyCases: [NormalizedReportedFrequencyCase]

  struct Memory: Decodable {
    let lastBroadcastFMFrequencyHz: Int
    let lastOIRTFrequencyHz: Int
    let lastLWFrequencyHz: Int
    let lastMWFrequencyHz: Int
    let lastSWFrequencyHz: Int
    let lastSelectedFMQuickBand: String
    let lastSelectedAMQuickBand: String
  }

  struct QuickBandCase: Decodable {
    let label: String
    let frequencyHz: Int
    let mode: String
    let expectedQuickBand: String
  }

  struct InferredModeCase: Decodable {
    let label: String
    let frequencyHz: Int
    let expectedMode: String
  }

  struct PreferredFrequencyCase: Decodable {
    let label: String
    let mode: String?
    let band: String?
    let memory: Memory
    let expectedQuickBand: String?
    let expectedFrequencyHz: Int
  }

  struct RememberCase: Decodable {
    let label: String
    let frequencyHz: Int
    let mode: String
    let initialMemory: Memory
    let expectedMemory: Memory
  }

  struct SeedCase: Decodable {
    let label: String
    let frequencyHz: Int
    let initialMemory: Memory
    let expectedMemory: Memory
  }

  struct NormalizedReportedFrequencyCase: Decodable {
    let label: String
    let inputMHz: Double
    let expectedFrequencyHz: Int
  }
}

struct ChannelScannerSignalCoreFixtureSet: Decodable {
  let defaultThresholdCases: [DefaultThresholdCase]
  let signalUnitCases: [SignalUnitCase]
  let adaptiveDwellCases: [AdaptiveTimingCase]
  let adaptiveHoldCases: [AdaptiveTimingCase]
  let thresholdCases: [ThresholdCase]
  let interferenceStateCases: [InterferenceStateCase]

  struct DefaultThresholdCase: Decodable {
    let label: String
    let backend: String
    let expected: Double
  }

  struct SignalUnitCase: Decodable {
    let label: String
    let backend: String?
    let expected: String
  }

  struct AdaptiveTimingCase: Decodable {
    let label: String
    let base: Double
    let adaptive: Bool
    let signal: Double?
    let threshold: Double
    let expected: Double
  }

  struct ThresholdCase: Decodable {
    let label: String
    let profile: String
    let expected: Thresholds
  }

  struct Thresholds: Decodable {
    let minimumAnalysisBuffers: Int
    let maximumSampleAgeSeconds: Double
    let stationaryEnvelopeLevelStdDB: Double
    let stationaryEnvelopeVariation: Double
    let lowFrequencyHumLevelStdDB: Double
    let lowFrequencyHumZeroCrossingRate: Double
    let lowFrequencyHumSpectralActivity: Double
    let widebandStaticLevelStdDB: Double
    let widebandStaticEnvelopeVariation: Double
    let widebandStaticMinimumZeroCrossingRate: Double
    let widebandStaticMinimumSpectralActivity: Double
  }

  struct InterferenceStateCase: Decodable {
    let label: String
    let profile: String
    let metrics: Metrics?
    let expected: String?
  }

  struct Metrics: Decodable {
    let sampleAgeSeconds: Double?
    let analysisBufferCount: Int
    let envelopeVariation: Double?
    let zeroCrossingRate: Double?
    let spectralActivity: Double?
    let levelStdDB: Double?
  }
}

struct FMDXScannerCoreFixtureSet: Decodable {
  let availablePresetCases: [AvailablePresetCase]
  let definitionCases: [DefinitionCase]
  let selectableModeCases: [SelectableModeCase]
  let sequenceCases: [SequenceCase]
  let timingCases: [TimingCase]
  let reducerCases: [ReducerCase]
  let matcherCases: [MatcherCase]

  struct AvailablePresetCase: Decodable {
    let label: String
    let supportsAM: Bool
    let expectedPresets: [String]
  }

  struct DefinitionCase: Decodable {
    let label: String
    let preset: String
    let expected: Definition
  }

  struct Definition: Decodable {
    let mode: String
    let rangeLowerHz: Int
    let rangeUpperHz: Int
    let stepOptionsHz: [Int]
    let defaultStepHz: Int
    let metadataProfileBand: String
    let mergeSpacingProfileBand: String
  }

  struct SelectableModeCase: Decodable {
    let label: String
    let saveResultsEnabled: Bool
    let expectedModes: [String]
  }

  struct SequenceCase: Decodable {
    let label: String
    let rangeLowerHz: Int
    let rangeUpperHz: Int
    let stepHz: Int
    let startBehavior: String
    let currentFrequencyHz: Int?
    let expectedFrequenciesHz: [Int]
  }

  struct TimingCase: Decodable {
    let label: String
    let mode: String
    let band: String
    let settleSeconds: Double
    let metadataWindowSeconds: Double
    let expected: TimingProfile
  }

  struct TimingProfile: Decodable {
    let tuneAttemptCount: Int
    let settleSeconds: Double
    let minimumDeadlineSeconds: Double
    let confirmationGraceSeconds: Double
    let minimumPostLockSettleSeconds: Double
    let metadataWindowSeconds: Double
    let minimumMetadataWindowSeconds: Double
    let metadataPollSeconds: Double
  }

  struct Sample: Decodable {
    let frequencyHz: Int
    let mode: String
    let signal: Double
    let signalTop: Double?
    let stationName: String?
    let programService: String?
    let radioText0: String?
    let radioText1: String?
    let city: String?
    let countryName: String?
    let distanceKm: String?
    let erpKW: String?
    let userCount: Int?
  }

  struct Result: Decodable {
    let frequencyHz: Int
    let mode: String
    let signal: Double
    let signalTop: Double?
    let stationName: String?
    let programService: String?
    let radioText0: String?
    let radioText1: String?
    let city: String?
    let countryName: String?
    let distanceKm: String?
    let erpKW: String?
    let userCount: Int?
  }

  struct ReducerCase: Decodable {
    let label: String
    let mergeSpacingHz: Int
    let samples: [Sample]
    let expectedResults: [Result]
  }

  struct MatcherCase: Decodable {
    let label: String
    let savedResults: [Result]
    let candidateResults: [Result]
    let expectedNewResultFrequenciesHz: [Int]
  }
}

struct FMDXTelemetrySyncCoreFixtureSet: Decodable {
  let toggleCases: [ToggleCase]
  let bandwidthSelectionCases: [BandwidthSelectionCase]
  let syncCases: [SyncCase]

  struct ToggleCase: Decodable {
    let label: String
    let input: String?
    let expected: Bool?
  }

  struct BandwidthOption: Decodable {
    let id: String
    let legacyValue: String?
  }

  struct BandwidthSelectionCase: Decodable {
    let label: String
    let rawValue: String
    let capabilities: [BandwidthOption]
    let expected: String
  }

  struct Settings: Decodable {
    let frequencyHz: Int
    let tuneStepHz: Int
    let preferredTuneStepHz: Int
    let tuneStepPreferenceMode: String
    let mode: String
    let agcEnabled: Bool
    let noiseReductionEnabled: Bool
    let imsEnabled: Bool
  }

  struct Telemetry: Decodable {
    let frequencyMHz: Double?
    let audioMode: String?
    let antenna: String?
    let bandwidth: String?
    let agc: String?
    let eq: String?
    let ims: String?
  }

  struct Capabilities: Decodable {
    let bandwidths: [BandwidthOption]
  }

  struct Input: Decodable {
    let settings: Settings
    let telemetry: Telemetry
    let capabilities: Capabilities
    let bandMemory: FMDXSessionCoreFixtureSet.Memory
    let pendingTuneFrequencyHz: Int?
  }

  struct Expected: Decodable {
    let settings: Settings
    let bandMemory: FMDXSessionCoreFixtureSet.Memory
    let audioMode: String?
    let antennaID: String?
    let bandwidthID: String?
    let changedSettings: Bool
    let shouldClearPendingTuneConfirmation: Bool
    let reportedFrequencyHz: Int?
    let reportedMode: String?
  }

  struct SyncCase: Decodable {
    let label: String
    let input: Input
    let expected: Expected
  }
}

struct FMDXCapabilitiesSyncCoreFixtureSet: Decodable {
  let syncCases: [SyncCase]

  struct Settings: Decodable {
    let frequencyHz: Int
    let tuneStepHz: Int
    let preferredTuneStepHz: Int
    let tuneStepPreferenceMode: String
    let mode: String
  }

  struct Input: Decodable {
    let settings: Settings
    let selectedBandwidthID: String?
    let capabilities: FMDXTelemetrySyncCoreFixtureSet.Capabilities
  }

  struct Expected: Decodable {
    let settings: Settings
    let resolvedBandwidthID: String?
    let changedSettings: Bool
    let forcedFMBandFallback: Bool
  }

  struct SyncCase: Decodable {
    let label: String
    let input: Input
    let expected: Expected
  }
}

struct FMDXCapabilitiesPolicyCoreFixtureSet: Decodable {
  let cases: [Case]

  struct ControlOption: Decodable {
    let id: String
    let label: String?
    let legacyValue: String?
  }

  struct Capabilities: Decodable {
    let antennas: [ControlOption]
    let bandwidths: [ControlOption]
    let supportsAM: Bool
    let supportsFilterControls: Bool
    let supportsAGCControl: Bool
  }

  struct Case: Decodable {
    let label: String
    let capabilities: Capabilities
    let expected: Bool
  }
}

struct FMDXCapabilitiesMergeCoreFixtureSet: Decodable {
  let cases: [Case]

  struct Input: Decodable {
    let primary: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
    let fallback: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities?
  }

  struct Case: Decodable {
    let label: String
    let input: Input
    let expected: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
  }
}

struct FMDXCapabilitiesCacheCoreFixtureSet: Decodable {
  let cases: [Case]

  struct Input: Decodable {
    let primary: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
    let fallback: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities?
  }

  struct Expected: Decodable {
    let capabilities: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
    let usedFallbackCapabilities: Bool
    let primarySnapshotWasMeaningful: Bool
    let shouldPersistResolvedCapabilities: Bool
  }

  struct Case: Decodable {
    let label: String
    let input: Input
    let expected: Expected
  }
}

struct FMDXCapabilitiesSessionCoreFixtureSet: Decodable {
  let restoreCases: [RestoreCase]
  let connectedCases: [ConnectedCase]

  struct Expected: Decodable {
    let capabilities: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
    let hasConfirmedSnapshot: Bool
    let usedCachedCapabilities: Bool
  }

  struct RestoreCase: Decodable {
    let label: String
    let cached: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities?
    let expected: Expected
  }

  struct Resolution: Decodable {
    let capabilities: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities
    let usedFallbackCapabilities: Bool
    let primarySnapshotWasMeaningful: Bool
    let shouldPersistResolvedCapabilities: Bool
  }

  struct ConnectedCase: Decodable {
    let label: String
    let resolution: Resolution
    let expected: Expected
  }
}

struct InitialServerTuningSyncCoreFixtureSet: Decodable {
  let deadlineCases: [DeadlineCase]
  let statusCases: [StatusCase]

  struct DeadlineCase: Decodable {
    let label: String
    let backend: String?
    let expectedSeconds: Double?
  }

  struct StatusCase: Decodable {
    let label: String
    let backend: String?
    let hasInitialServerTuningSync: Bool
    let deadlineReached: Bool
    let expected: Expected
  }

  struct Expected: Decodable {
    let requiresInitialServerTuningSync: Bool
    let canApplyLocalTuning: Bool
    let isWaitingForInitialServerTuningSync: Bool
    let shouldApplyInitialLocalFallback: Bool
  }
}

struct DeferredSessionRestoreCoreFixtureSet: Decodable {
  let constantCases: [ConstantCase]
  let statusCases: [StatusCase]

  struct ConstantCase: Decodable {
    let label: String
    let expectedDeadlineSeconds: Double
    let expectedPollIntervalSeconds: Double
  }

  struct StatusCase: Decodable {
    let label: String
    let isConnected: Bool
    let isTargetProfileConnected: Bool
    let canApplyLocalTuning: Bool
    let deadlineReached: Bool
    let expected: Expected
  }

  struct Expected: Decodable {
    let shouldApply: Bool
    let shouldContinueWaiting: Bool
  }
}

struct ConnectedSessionRestoreCoreFixtureSet: Decodable {
  let cases: [Case]

  struct Case: Decodable {
    let label: String
    let backend: String?
    let frequencyHz: Int?
    let mode: String?
    let hasInitialServerTuningSync: Bool
    let deadlineReached: Bool
    let expectedAction: String
  }
}

struct AutomaticReconnectCoreFixtureSet: Decodable {
  let expectedRetryWindowSeconds: Double
  let delayCases: [DelayCase]
  let retryCases: [RetryCase]

  struct DelayCase: Decodable {
    let label: String
    let attemptNumber: Int
    let expectedDelaySeconds: Double
  }

  struct RetryCase: Decodable {
    let label: String
    let elapsedSeconds: Double
    let expectedShouldContinueRetrying: Bool
  }
}

struct SavedSettingsSnapshotCoreFixtureSet: Decodable {
  let createCases: [CreateCase]
  let restoreCases: [RestoreCase]

  struct State: Decodable {
    let frequencyHz: Int
    let dxNightModeEnabled: Bool
    let autoFilterProfileEnabled: Bool
  }

  struct CreateCase: Decodable {
    let label: String
    let current: State
    let expected: State
  }

  struct RestoreCase: Decodable {
    let label: String
    let includeFrequency: Bool
    let current: State
    let snapshot: State
    let expected: State
  }
}

struct URLFixture: Decodable {
  let scheme: String
  let userInfo: String?
  let host: String
  let port: Int
  let path: String
  let asString: String?
}

struct IntRangeFixture: Decodable {
  let lower: Int
  let upper: Int
}

struct ReceiverDirectoryEndpointFixture: Decodable {
  let host: String
  let port: Int
  let path: String
  let useTLS: Bool
  let absoluteURL: String
}

extension FrequencyInputParser.Context {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "generic":
      self = .generic
    case "fmBroadcast":
      self = .fmBroadcast
    case "shortwave":
      self = .shortwave
    default:
      throw FixtureError.invalidFixtureValue("Unknown frequency parser context fixture: \(fixtureValue)")
    }
  }
}

extension SDRBackend {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "kiwiSDR":
      self = .kiwiSDR
    case "openWebRX":
      self = .openWebRX
    case "fmDxWebserver":
      self = .fmDxWebserver
    default:
      throw FixtureError.invalidFixtureValue("Unknown SDR backend fixture: \(fixtureValue)")
    }
  }
}

extension DemodulationMode {
  init(fixtureValue: String) throws {
    guard let mode = DemodulationMode(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown demodulation mode fixture: \(fixtureValue)")
    }
    self = mode
  }
}

extension ConnectedSessionRestoreAction {
  init(fixtureValue: String) throws {
    guard let value = ConnectedSessionRestoreAction(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown connected session restore action fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension TuneStepPreferenceMode {
  init(fixtureValue: String) throws {
    guard let value = TuneStepPreferenceMode(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown tune step preference fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXQuickBand {
  init(fixtureValue: String) throws {
    guard let value = FMDXQuickBand(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown FMDX quick band fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension ChannelScannerInterferenceFilterProfile {
  init(fixtureValue: String) throws {
    guard let value = ChannelScannerInterferenceFilterProfile(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown channel scanner interference profile fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXBandMemory {
  init(fixture: FMDXSessionCoreFixtureSet.Memory) throws {
    self.init(
      lastBroadcastFMFrequencyHz: fixture.lastBroadcastFMFrequencyHz,
      lastOIRTFrequencyHz: fixture.lastOIRTFrequencyHz,
      lastLWFrequencyHz: fixture.lastLWFrequencyHz,
      lastMWFrequencyHz: fixture.lastMWFrequencyHz,
      lastSWFrequencyHz: fixture.lastSWFrequencyHz,
      lastSelectedFMQuickBand: try FMDXQuickBand(fixtureValue: fixture.lastSelectedFMQuickBand),
      lastSelectedAMQuickBand: try FMDXQuickBand(fixtureValue: fixture.lastSelectedAMQuickBand)
    )
  }
}

extension FMDXBandScanRangePreset {
  init(fixtureValue: String) throws {
    guard let value = FMDXBandScanRangePreset(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown FMDX band scan range preset fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXBandScanMode {
  init(fixtureValue: String) throws {
    guard let value = FMDXBandScanMode(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown FMDX band scan mode fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXBandScanStartBehavior {
  init(fixtureValue: String) throws {
    guard let value = FMDXBandScanStartBehavior(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown FMDX scan start behavior fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXTelemetrySyncCore.AudioMode {
  init(fixtureValue: String) throws {
    guard let value = FMDXTelemetrySyncCore.AudioMode(rawValue: fixtureValue) else {
      throw FixtureError.invalidFixtureValue("Unknown FMDX audio mode fixture: \(fixtureValue)")
    }
    self = value
  }
}

extension FMDXTelemetrySyncCore.BandwidthOption {
  init(fixture: FMDXTelemetrySyncCoreFixtureSet.BandwidthOption) {
    self.init(
      id: fixture.id,
      legacyValue: fixture.legacyValue
    )
  }
}

extension FMDXCapabilitiesPolicyCore.ControlOption {
  init(fixture: FMDXCapabilitiesPolicyCoreFixtureSet.ControlOption) {
    self.init(
      id: fixture.id,
      label: fixture.label,
      legacyValue: fixture.legacyValue
    )
  }
}

extension FMDXCapabilitiesPolicyCore.Capabilities {
  init(fixture: FMDXCapabilitiesPolicyCoreFixtureSet.Capabilities) {
    self.init(
      antennas: fixture.antennas.map(FMDXCapabilitiesPolicyCore.ControlOption.init),
      bandwidths: fixture.bandwidths.map(FMDXCapabilitiesPolicyCore.ControlOption.init),
      supportsAM: fixture.supportsAM,
      supportsFilterControls: fixture.supportsFilterControls,
      supportsAGCControl: fixture.supportsAGCControl
    )
  }
}

extension FMDXTelemetrySyncCore.Capabilities {
  init(fixture: FMDXTelemetrySyncCoreFixtureSet.Capabilities) {
    self.init(
      bandwidths: fixture.bandwidths.map(FMDXTelemetrySyncCore.BandwidthOption.init)
    )
  }
}

extension FMDXTelemetrySyncCore.SettingsSnapshot {
  init(fixture: FMDXTelemetrySyncCoreFixtureSet.Settings) throws {
    self.init(
      frequencyHz: fixture.frequencyHz,
      tuneStepHz: fixture.tuneStepHz,
      preferredTuneStepHz: fixture.preferredTuneStepHz,
      tuneStepPreferenceMode: try TuneStepPreferenceMode(fixtureValue: fixture.tuneStepPreferenceMode),
      mode: try DemodulationMode(fixtureValue: fixture.mode),
      agcEnabled: fixture.agcEnabled,
      noiseReductionEnabled: fixture.noiseReductionEnabled,
      imsEnabled: fixture.imsEnabled
    )
  }
}

extension FMDXCapabilitiesSyncCore.SettingsSnapshot {
  init(fixture: FMDXCapabilitiesSyncCoreFixtureSet.Settings) throws {
    self.init(
      frequencyHz: fixture.frequencyHz,
      tuneStepHz: fixture.tuneStepHz,
      preferredTuneStepHz: fixture.preferredTuneStepHz,
      tuneStepPreferenceMode: try TuneStepPreferenceMode(fixtureValue: fixture.tuneStepPreferenceMode),
      mode: try DemodulationMode(fixtureValue: fixture.mode)
    )
  }
}

extension FMDXTelemetrySyncCore.Telemetry {
  init(fixture: FMDXTelemetrySyncCoreFixtureSet.Telemetry) throws {
    self.init(
      frequencyMHz: fixture.frequencyMHz,
      audioMode: try fixture.audioMode.map(FMDXTelemetrySyncCore.AudioMode.init(fixtureValue:)),
      antenna: fixture.antenna,
      bandwidth: fixture.bandwidth,
      agc: fixture.agc,
      eq: fixture.eq,
      ims: fixture.ims
    )
  }
}

extension FMDXBandScanSample {
  init(fixture: FMDXScannerCoreFixtureSet.Sample) throws {
    self.init(
      frequencyHz: fixture.frequencyHz,
      mode: try DemodulationMode(fixtureValue: fixture.mode),
      signal: fixture.signal,
      signalTop: fixture.signalTop,
      stationName: fixture.stationName,
      programService: fixture.programService,
      radioText0: fixture.radioText0,
      radioText1: fixture.radioText1,
      city: fixture.city,
      countryName: fixture.countryName,
      distanceKm: fixture.distanceKm,
      erpKW: fixture.erpKW,
      userCount: fixture.userCount
    )
  }
}

extension FMDXBandScanResult {
  init(fixture: FMDXScannerCoreFixtureSet.Result) throws {
    self.init(
      frequencyHz: fixture.frequencyHz,
      mode: try DemodulationMode(fixtureValue: fixture.mode),
      signal: fixture.signal,
      signalTop: fixture.signalTop,
      stationName: fixture.stationName,
      programService: fixture.programService,
      radioText0: fixture.radioText0,
      radioText1: fixture.radioText1,
      city: fixture.city,
      countryName: fixture.countryName,
      distanceKm: fixture.distanceKm,
      erpKW: fixture.erpKW,
      userCount: fixture.userCount
    )
  }
}

extension ReceiverImportBackend {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "kiwiSDR":
      self = .kiwiSDR
    case "openWebRX":
      self = .openWebRX
    case "fmDxWebserver":
      self = .fmDxWebserver
    default:
      throw FixtureError.invalidFixtureValue("Unknown receiver backend fixture: \(fixtureValue)")
    }
  }
}

extension ReceiverDirectoryParsingCoreErrorCode {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "unsupportedReceiverbookFormat":
      self = .unsupportedReceiverbookFormat
    default:
      throw FixtureError.invalidFixtureValue("Unknown receiver directory parsing error fixture: \(fixtureValue)")
    }
  }
}

extension SharedReceiverDirectoryStatus {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "available":
      self = .available
    case "limited":
      self = .limited
    case "unreachable":
      self = .unreachable
    case "unknown":
      self = .unknown
    default:
      throw FixtureError.invalidFixtureValue(
        "Unknown receiver directory status fixture: \(fixtureValue)"
      )
    }
  }
}

extension SharedReceiverDirectoryStatusFilter {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "all":
      self = .all
    case "online":
      self = .online
    case "availableOnly":
      self = .availableOnly
    case "unavailable":
      self = .unavailable
    default:
      throw FixtureError.invalidFixtureValue(
        "Unknown receiver directory status filter fixture: \(fixtureValue)"
      )
    }
  }
}

extension SharedReceiverDirectoryCountrySortOption {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "alphabetical":
      self = .alphabetical
    case "receiverCount":
      self = .receiverCount
    default:
      throw FixtureError.invalidFixtureValue(
        "Unknown receiver directory country sort fixture: \(fixtureValue)"
      )
    }
  }
}

extension SharedReceiverDirectorySortOption {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "recommended":
      self = .recommended
    case "name":
      self = .name
    case "location":
      self = .location
    case "status":
      self = .status
    case "source":
      self = .source
    default:
      throw FixtureError.invalidFixtureValue(
        "Unknown receiver directory sort fixture: \(fixtureValue)"
      )
    }
  }
}

extension SharedReceiverDirectoryEntry {
  init(fixture: ReceiverDirectorySelectionFixtureSet.Entry) throws {
    self.init(
      id: fixture.id,
      backend: try SDRBackend(fixtureValue: fixture.backend),
      name: fixture.name,
      sourceName: fixture.sourceName,
      status: try SharedReceiverDirectoryStatus(fixtureValue: fixture.status),
      countryLabel: fixture.countryLabel,
      locationLabel: fixture.locationLabel,
      searchableText: fixture.searchableText,
      detailText: fixture.detailText,
      receiverIdentity: fixture.receiverIdentity
    )
  }
}

extension ReceiverLinkImportCoreErrorCode {
  init(fixtureValue: String) throws {
    switch fixtureValue {
    case "emptyInput":
      self = .emptyInput
    case "invalidURL":
      self = .invalidURL
    case "missingHost":
      self = .missingHost
    case "couldNotDetectReceiver":
      self = .couldNotDetectReceiver
    default:
      throw FixtureError.invalidFixtureValue("Unknown receiver link error fixture: \(fixtureValue)")
    }
  }
}
