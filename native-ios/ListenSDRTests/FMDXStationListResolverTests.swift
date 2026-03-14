import XCTest
@testable import ListenSDR

final class FMDXStationListResolverTests: XCTestCase {
  func testRecognizesGenericPluginPresetList() async {
    let client = FMDXWebserverClient()
    let genericPluginList = [
      SDRServerBookmark(id: "1", name: "R.Piekary", frequencyHz: 89_100_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "2", name: "Radio 90", frequencyHz: 89_700_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "3", name: "Express FM", frequencyHz: 94_200_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "4", name: "Silesia", frequencyHz: 94_400_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "5", name: "Piraci Śląsk", frequencyHz: 94_700_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "6", name: "R.Fest", frequencyHz: 94_800_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "7", name: "Katowice", frequencyHz: 96_400_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "8", name: "Radio Zet", frequencyHz: 98_400_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "9", name: "R.Opole", frequencyHz: 99_000_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "10", name: "AntyRadio", frequencyHz: 103_400_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "11", name: "R.Bielsko", frequencyHz: 104_500_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "12", name: "Radio eM", frequencyHz: 107_400_000, modulation: .fm, source: "plugin")
    ]

    let isGeneric = await client.isGenericFMDXPluginPresetList(genericPluginList)

    XCTAssertTrue(isGeneric)
  }

  func testBuildsStaticPresetBookmarksWithoutFakeNamesForUnmatchedFrequencies() async {
    let client = FMDXWebserverClient()
    let staticData: [String: Any] = [
      "presets": ["94.7", "96.9", "105.4", "98.9"]
    ]
    let genericPluginList = [
      SDRServerBookmark(id: "1", name: "R.Piekary", frequencyHz: 89_100_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "2", name: "Radio 90", frequencyHz: 89_700_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "3", name: "Express FM", frequencyHz: 94_200_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "4", name: "Silesia", frequencyHz: 94_400_000, modulation: .fm, source: "plugin")
    ]

    let bookmarks = await client.buildFMDXStaticPresetBookmarks(
      staticData: staticData,
      pluginBookmarks: genericPluginList
    )

    XCTAssertEqual(bookmarks.map(\.frequencyHz), [94_700_000, 96_900_000, 98_900_000, 105_400_000])
    XCTAssertEqual(
      bookmarks.map(\.name),
      ["94,7 MHz", "96,9 MHz", "98,9 MHz", "105,4 MHz"]
    )
  }

  func testBuildsStaticPresetBookmarksUsingMatchedPluginNamesOnly() async {
    let client = FMDXWebserverClient()
    let staticData: [String: Any] = [
      "presets": ["89.1", "89.7", "98.4"]
    ]
    let pluginList = [
      SDRServerBookmark(id: "1", name: "Relax FM", frequencyHz: 89_100_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "2", name: "ADHD", frequencyHz: 89_700_000, modulation: .fm, source: "plugin"),
      SDRServerBookmark(id: "3", name: "Rave FM", frequencyHz: 98_400_000, modulation: .fm, source: "plugin")
    ]

    let bookmarks = await client.buildFMDXStaticPresetBookmarks(
      staticData: staticData,
      pluginBookmarks: pluginList
    )

    XCTAssertEqual(bookmarks.map(\.name), ["Relax FM", "ADHD", "Rave FM"])
  }
}
