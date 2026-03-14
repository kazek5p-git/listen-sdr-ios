import XCTest
@testable import ListenSDR

final class FMDXPresetScriptParserTests: XCTestCase {
  func testParsesLegacyDefaultPresetDataFromButtonPresetsPlugin() {
    let script = """
    const pluginButtonPresets = true;
    const defaultPresetData = {
      values: [89.1, 89.7, 94.2, 94.4, 94.7, 94.8, 96.4, 98.4, 99.0, 103.4, 104.5, 107.4],
      antennas: ['', '', '', '', '', '', '', '', '', ''],
      names: ['R.Piekary', 'Radio 90', 'Express FM', 'Silesia', 'Piraci Śląsk', 'R.Fest', 'Katowice', 'Radio Zet', 'R.Opole', 'AntyRadio', 'R.Bielsko', 'Radio eM'],
      urls: ['', '', '', '', '', '', '', '', '', '']
    };
    """

    let bookmarks = FMDXPresetScriptParser.parseBookmarks(from: script)

    XCTAssertEqual(bookmarks.count, 12)
    XCTAssertEqual(bookmarks.first?.name, "R.Piekary")
    XCTAssertEqual(bookmarks.first?.frequencyHz, 89_100_000)
    XCTAssertEqual(bookmarks.last?.name, "Radio eM")
    XCTAssertEqual(bookmarks.last?.frequencyHz, 107_400_000)
  }

  func testPrefersTooltipsOverShortNamesForVisibleStationList() {
    let script = """
    const pluginButtonPresets = true;
    const defaultPresetData = {
      values: [88.4, 91.5, 105.4],
      names: [' Zlote  ', ' RMF FM ', ' Rock   '],
      urls: ['/logos/32CC.png', '/logos/3F44.png', '/logos/32AB.png'],
      tooltips: ['Radio Zlote Przeboje', 'RMF FM', 'Rock Radio']
    };
    """

    let bookmarks = FMDXPresetScriptParser.parseBookmarks(from: script)

    XCTAssertEqual(bookmarks.count, 3)
    XCTAssertEqual(bookmarks[0].name, "Radio Zlote Przeboje")
    XCTAssertEqual(bookmarks[1].name, "RMF FM")
    XCTAssertEqual(bookmarks[2].name, "Rock Radio")
  }

  func testParsesLocalStorageFallbackPresetBlockWhenDefaultPresetDataIsMissing() {
    let script = #"""
    function getStoredData(bank) {
      const key = `buttonPresets${bank}`;
      let dataButtonPresets;
      if (bank === "A") {
        dataButtonPresets = JSON.parse(localStorage.getItem(key)) || {
          values: [88.1, 89.1, 89.7],
          ps: ['XOXO!', 'Relax FM', 'ADHD'],
          images: ['', '', ''],
          tooltips: ['XOXO!', 'Relax FM', 'ADHD']
        };
      }
      return dataButtonPresets;
    }
    """#

    let bookmarks = FMDXPresetScriptParser.parseBookmarks(from: script)

    XCTAssertEqual(bookmarks.map(\.name), ["XOXO!", "Relax FM", "ADHD"])
    XCTAssertEqual(bookmarks.map(\.frequencyHz), [88_100_000, 89_100_000, 89_700_000])
  }

  func testRequiresPresetMarkerRejectsUnrelatedScripts() {
    let script = "const values = [89.1, 89.7, 98.4]; const names = ['A', 'B', 'C'];"

    let bookmarks = FMDXPresetScriptParser.parseBookmarks(from: script, requiresPresetMarker: true)

    XCTAssertTrue(bookmarks.isEmpty)
  }
}
