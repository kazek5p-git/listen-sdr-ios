import Foundation

struct RecordingDestinationInfo {
  let isCustomSelected: Bool
  let summary: String
}

struct RecordingFolderSelection {
  let url: URL
  let isSecurityScoped: Bool
  let isCustomSelected: Bool
}

final class RecordingDestinationStore {
  static let shared = RecordingDestinationStore()

  private let bookmarkKey = "ListenSDR.recordingsFolderBookmark.v1"
  private let fileManager = FileManager.default
  private let userDefaults = UserDefaults.standard

  private init() {}

  func currentDestinationInfo(defaultFolderURL: URL) -> RecordingDestinationInfo {
    if let customFolderURL = resolvedCustomFolderURL() {
      return RecordingDestinationInfo(
        isCustomSelected: true,
        summary: customFolderURL.lastPathComponent
      )
    }

    return RecordingDestinationInfo(
      isCustomSelected: false,
      summary: defaultFolderURL.path
    )
  }

  func currentFolderSelection(defaultFolderURL: URL) -> RecordingFolderSelection {
    if let customFolderURL = resolvedCustomFolderURL() {
      return RecordingFolderSelection(
        url: customFolderURL,
        isSecurityScoped: true,
        isCustomSelected: true
      )
    }

    return RecordingFolderSelection(
      url: defaultFolderURL,
      isSecurityScoped: false,
      isCustomSelected: false
    )
  }

  func saveCustomFolderURL(_ url: URL?) throws {
    guard let url else {
      userDefaults.removeObject(forKey: bookmarkKey)
      return
    }

    let bookmarkData = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    userDefaults.set(bookmarkData, forKey: bookmarkKey)
  }

  func withFolderAccess<T>(
    selection: RecordingFolderSelection,
    _ body: (URL) throws -> T
  ) rethrows -> T {
    let granted = selection.isSecurityScoped ? selection.url.startAccessingSecurityScopedResource() : false
    defer {
      if granted {
        selection.url.stopAccessingSecurityScopedResource()
      }
    }
    return try body(selection.url)
  }

  private func resolvedCustomFolderURL() -> URL? {
    guard let bookmarkData = userDefaults.data(forKey: bookmarkKey) else { return nil }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }

    if isStale {
      try? saveCustomFolderURL(url)
    }

    let granted = url.startAccessingSecurityScopedResource()
    defer {
      if granted {
        url.stopAccessingSecurityScopedResource()
      }
    }

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    return url
  }
}
