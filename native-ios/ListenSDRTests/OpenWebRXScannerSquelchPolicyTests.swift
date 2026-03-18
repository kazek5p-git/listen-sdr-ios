import XCTest
@testable import ListenSDR

final class OpenWebRXScannerSquelchPolicyTests: XCTestCase {
  func testEffectiveEnabledTurnsOffSquelchWhenScannerLockIsActive() {
    XCTAssertTrue(
      OpenWebRXScannerSquelchPolicy.effectiveEnabled(
        storedEnabled: true,
        isLockedByScanner: false
      )
    )
    XCTAssertFalse(
      OpenWebRXScannerSquelchPolicy.effectiveEnabled(
        storedEnabled: true,
        isLockedByScanner: true
      )
    )
  }

  func testApplyingOverrideDisablesSquelchOnlyForOpenWebRX() {
    var settings = RadioSessionSettings.default
    settings.squelchEnabled = true

    let openWebRXSnapshot = OpenWebRXScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: .openWebRX,
      isLockedByScanner: true
    )
    let kiwiSnapshot = OpenWebRXScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: .kiwiSDR,
      isLockedByScanner: true
    )
    let unlockedSnapshot = OpenWebRXScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: .openWebRX,
      isLockedByScanner: false
    )

    XCTAssertFalse(openWebRXSnapshot.squelchEnabled)
    XCTAssertTrue(kiwiSnapshot.squelchEnabled)
    XCTAssertTrue(unlockedSnapshot.squelchEnabled)
  }

  func testKiwiPolicyTurnsOffSquelchOnlyForKiwi() {
    var settings = RadioSessionSettings.default
    settings.squelchEnabled = true

    let kiwiSnapshot = KiwiScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: .kiwiSDR,
      isLockedByScanner: true
    )
    let openWebRXSnapshot = KiwiScannerSquelchPolicy.applyingOverride(
      to: settings,
      backend: .openWebRX,
      isLockedByScanner: true
    )

    XCTAssertFalse(
      KiwiScannerSquelchPolicy.effectiveEnabled(
        storedEnabled: true,
        isLockedByScanner: true
      )
    )
    XCTAssertFalse(kiwiSnapshot.squelchEnabled)
    XCTAssertTrue(openWebRXSnapshot.squelchEnabled)
  }
}
