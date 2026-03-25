import XCTest
@testable import ListenSDRCore

final class ChannelScannerSignalCoreTests: XCTestCase {
  func testDefaultThresholdsMatchCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.defaultThresholdCases {
      XCTAssertEqual(
        ChannelScannerSignalCore.defaultThreshold(for: try SDRBackend(fixtureValue: entry.backend)),
        entry.expected,
        accuracy: 0.0001,
        entry.label
      )
    }
  }

  func testSignalUnitsMatchCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.signalUnitCases {
      XCTAssertEqual(
        ChannelScannerSignalCore.signalUnit(for: try entry.backend.map(SDRBackend.init(fixtureValue:))),
        entry.expected,
        entry.label
      )
    }
  }

  func testAdaptiveDwellMatchesCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.adaptiveDwellCases {
      XCTAssertEqual(
        ChannelScannerSignalCore.adaptiveDwellSeconds(
          entry.base,
          adaptive: entry.adaptive,
          signal: entry.signal,
          threshold: entry.threshold
        ),
        entry.expected,
        accuracy: 0.0001,
        entry.label
      )
    }
  }

  func testAdaptiveHoldMatchesCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.adaptiveHoldCases {
      XCTAssertEqual(
        ChannelScannerSignalCore.adaptiveHoldSeconds(
          entry.base,
          adaptive: entry.adaptive,
          signal: entry.signal,
          threshold: entry.threshold
        ),
        entry.expected,
        accuracy: 0.0001,
        entry.label
      )
    }
  }

  func testInterferenceThresholdsMatchCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.thresholdCases {
      let thresholds = ChannelScannerSignalCore.interferenceFilterThresholds(
        for: try ChannelScannerInterferenceFilterProfile(fixtureValue: entry.profile)
      )

      XCTAssertEqual(thresholds.minimumAnalysisBuffers, entry.expected.minimumAnalysisBuffers, entry.label)
      XCTAssertEqual(thresholds.maximumSampleAgeSeconds, entry.expected.maximumSampleAgeSeconds, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.stationaryEnvelopeLevelStdDB, entry.expected.stationaryEnvelopeLevelStdDB, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.stationaryEnvelopeVariation, entry.expected.stationaryEnvelopeVariation, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.lowFrequencyHumLevelStdDB, entry.expected.lowFrequencyHumLevelStdDB, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.lowFrequencyHumZeroCrossingRate, entry.expected.lowFrequencyHumZeroCrossingRate, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.lowFrequencyHumSpectralActivity, entry.expected.lowFrequencyHumSpectralActivity, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.widebandStaticLevelStdDB, entry.expected.widebandStaticLevelStdDB, accuracy: 0.0001, entry.label)
      XCTAssertEqual(thresholds.widebandStaticEnvelopeVariation, entry.expected.widebandStaticEnvelopeVariation, accuracy: 0.0001, entry.label)
      XCTAssertEqual(
        thresholds.widebandStaticMinimumZeroCrossingRate,
        entry.expected.widebandStaticMinimumZeroCrossingRate,
        accuracy: 0.0001,
        entry.label
      )
      XCTAssertEqual(
        thresholds.widebandStaticMinimumSpectralActivity,
        entry.expected.widebandStaticMinimumSpectralActivity,
        accuracy: 0.0001,
        entry.label
      )
    }
  }

  func testInterferenceStateMatchesCanonicalFixtures() throws {
    let fixture: ChannelScannerSignalCoreFixtureSet = try FixtureLoader.load("channel-scanner-signal-core-cases.json")

    for entry in fixture.interferenceStateCases {
      let metrics = entry.metrics.map {
        ChannelScannerInterferenceMetrics(
          sampleAgeSeconds: $0.sampleAgeSeconds,
          analysisBufferCount: $0.analysisBufferCount,
          envelopeVariation: $0.envelopeVariation,
          zeroCrossingRate: $0.zeroCrossingRate,
          spectralActivity: $0.spectralActivity,
          levelStdDB: $0.levelStdDB
        )
      }

      XCTAssertEqual(
        ChannelScannerSignalCore.interferenceFilterState(
          metrics: metrics,
          profile: try ChannelScannerInterferenceFilterProfile(fixtureValue: entry.profile)
        ),
        entry.expected,
        entry.label
      )
    }
  }
}
