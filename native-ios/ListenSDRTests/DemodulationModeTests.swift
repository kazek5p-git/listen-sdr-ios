import XCTest
@testable import ListenSDR

final class DemodulationModeTests: XCTestCase {
  func testKiwiSupportedModesMatchExpectedOfficialSubset() {
    XCTAssertEqual(
      DemodulationMode.kiwiSupportedModes,
      [.am, .amn, .amw, .nfm, .nnfm, .usb, .usn, .lsb, .lsn, .cw, .cwn, .iq, .drm, .sam, .sau, .sal, .sas, .qam]
    )
  }

  func testOpenWebRXSupportedModesRemainConservative() {
    XCTAssertEqual(
      DemodulationMode.openWebRXSupportedModes,
      [.am, .fm, .nfm, .usb, .lsb, .cw]
    )
  }

  func testParsesExtendedKiwiModes() {
    XCTAssertEqual(DemodulationMode.fromKiwi("amn"), .amn)
    XCTAssertEqual(DemodulationMode.fromKiwi("amw"), .amw)
    XCTAssertEqual(DemodulationMode.fromKiwi("usn"), .usn)
    XCTAssertEqual(DemodulationMode.fromKiwi("lsn"), .lsn)
    XCTAssertEqual(DemodulationMode.fromKiwi("cwn"), .cwn)
    XCTAssertEqual(DemodulationMode.fromKiwi("nnfm"), .nnfm)
    XCTAssertEqual(DemodulationMode.fromKiwi("iq"), .iq)
    XCTAssertEqual(DemodulationMode.fromKiwi("drm"), .drm)
    XCTAssertEqual(DemodulationMode.fromKiwi("sam"), .sam)
    XCTAssertEqual(DemodulationMode.fromKiwi("sau"), .sau)
    XCTAssertEqual(DemodulationMode.fromKiwi("sal"), .sal)
    XCTAssertEqual(DemodulationMode.fromKiwi("sas"), .sas)
    XCTAssertEqual(DemodulationMode.fromKiwi("qam"), .qam)
  }

  func testNormalizesModesForKiwiAndOpenWebRX() {
    XCTAssertEqual(DemodulationMode.fm.normalized(for: .kiwiSDR), .nfm)
    XCTAssertEqual(DemodulationMode.usn.normalized(for: .openWebRX), .usb)
    XCTAssertEqual(DemodulationMode.lsn.normalized(for: .openWebRX), .lsb)
    XCTAssertEqual(DemodulationMode.cwn.normalized(for: .openWebRX), .cw)
    XCTAssertEqual(DemodulationMode.nnfm.normalized(for: .openWebRX), .nfm)
    XCTAssertEqual(DemodulationMode.iq.normalized(for: .openWebRX), .am)
  }

  func testKiwiDefaultBandpassMatchesOfficialDefaultsForNewModes() {
    XCTAssertEqual(DemodulationMode.amn.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -2_500, highCut: 2_500))
    XCTAssertEqual(DemodulationMode.amw.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -6_000, highCut: 6_000))
    XCTAssertEqual(DemodulationMode.usn.kiwiDefaultBandpass, ReceiverBandpass(lowCut: 300, highCut: 2_400))
    XCTAssertEqual(DemodulationMode.lsn.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -2_400, highCut: -300))
    XCTAssertEqual(DemodulationMode.cwn.kiwiDefaultBandpass, ReceiverBandpass(lowCut: 470, highCut: 530))
    XCTAssertEqual(DemodulationMode.nnfm.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -3_000, highCut: 3_000))
    XCTAssertEqual(DemodulationMode.sau.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -2_450, highCut: 7_350))
    XCTAssertEqual(DemodulationMode.sal.kiwiDefaultBandpass, ReceiverBandpass(lowCut: -7_350, highCut: 2_450))
  }
}
