import XCTest
import ListenSDRCore
@testable import ListenSDR

final class OpenWebRXScannerSquelchPolicyTests: XCTestCase {
  func testEffectiveEnabledTurnsOffSquelchWhenScannerLockIsActive() {
    XCTAssertTrue(
      RuntimeAdjustedSettingsCore.effectiveSquelchEnabled(
        storedEnabled: true,
        isLockedByScanner: false
      )
    )
    XCTAssertFalse(
      RuntimeAdjustedSettingsCore.effectiveSquelchEnabled(
        storedEnabled: true,
        isLockedByScanner: true
      )
    )
  }

  func testAdjustedStateDisablesSquelchForLockedOpenWebRXApply() {
    let lockedState = RuntimeAdjustedSettingsCore.adjustedState(
      backend: .openWebRX,
      mode: .am,
      squelchEnabled: true,
      isSquelchLockedByScanner: true
    )
    let unlockedState = RuntimeAdjustedSettingsCore.adjustedState(
      backend: .openWebRX,
      mode: .am,
      squelchEnabled: true,
      isSquelchLockedByScanner: false
    )

    XCTAssertEqual(.am, lockedState.mode)
    XCTAssertFalse(lockedState.squelchEnabled)
    XCTAssertEqual(.am, unlockedState.mode)
    XCTAssertTrue(unlockedState.squelchEnabled)
  }

  func testAdjustedStatePreservesKiwiModeAliasesAndAppliesLock() {
    let lockedState = RuntimeAdjustedSettingsCore.adjustedState(
      backend: .kiwiSDR,
      mode: .amw,
      squelchEnabled: true,
      isSquelchLockedByScanner: true
    )
    let aliasState = RuntimeAdjustedSettingsCore.adjustedState(
      backend: .kiwiSDR,
      mode: .nnfm,
      squelchEnabled: true,
      isSquelchLockedByScanner: false
    )

    XCTAssertEqual(.amw, lockedState.mode)
    XCTAssertFalse(lockedState.squelchEnabled)
    XCTAssertEqual(.nnfm, aliasState.mode)
    XCTAssertTrue(aliasState.squelchEnabled)
  }

  func testRuntimeOpenWebRXSquelchControlDoesNotNeedModeToDisableGate() {
    XCTAssertEqual(-95, SquelchRuntimeControl.openWebRXSquelchLevel(enabled: true, level: -95))
    XCTAssertEqual(-150, SquelchRuntimeControl.openWebRXSquelchLevel(enabled: false, level: -95))
  }

  func testRuntimeKiwiSquelchControlDisablesGateWithoutTouchingMode() {
    XCTAssertEqual(
      SquelchRuntimeControl.KiwiCommand(enabledFlag: 1, max: 6),
      SquelchRuntimeControl.kiwiCommand(enabled: true, threshold: 6)
    )
    XCTAssertEqual(
      SquelchRuntimeControl.KiwiCommand(enabledFlag: 0, max: 0),
      SquelchRuntimeControl.kiwiCommand(enabled: false, threshold: 6)
    )
  }
}
