import SwiftUI
import UniformTypeIdentifiers

struct SettingsBackupDocument: FileDocument {
  static let defaultFilename = "ListenSDR-settings-backup.json"
  static var readableContentTypes: [UTType] { [.json] }

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try RadioSessionSettingsBackupCodec.validateBackupData(data)
    return FileWrapper(regularFileWithContents: data)
  }

  static func readData(from url: URL) throws -> Data {
    let needsAccess = url.startAccessingSecurityScopedResource()
    defer {
      if needsAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    let data = try Data(contentsOf: url)
    try RadioSessionSettingsBackupCodec.validateBackupData(data)
    return data
  }
}
